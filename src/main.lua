--[[
File: main.lua
Date: 2026-08-30
Author: WaterRun
Description: Routes the offline bootstrap lifecycle from the unique composition root.
]]

local MODULE_NAME = ...
local compact = require("compact")
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

local function ascii_diagnostic(value, maximum_bytes)
    return (safe_diagnostic(value, maximum_bytes):gsub(
        "[\128-\255]",
        function(byte) return string.format("\\x%02X", byte:byte()) end
    ))
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
    local line = "yaca: " .. code .. ": " .. ascii_diagnostic(message, 1024)
    if type(err) == "table" and type(err.suggestion) == "string" then
        line = line .. " (did you mean " .. ascii_diagnostic(err.suggestion, 128) .. "?)"
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
        publication = true,
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
    if components.publication ~= nil
        and (type(components.publication) ~= "table"
            or type(components.publication.publish_first) ~= "function"
            or type(components.publication.close) ~= "function")
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "Context publication must expose publish_first and close"
        )
    end
    if components.context_catalog ~= nil then
        local catalog = components.context_catalog
        if type(catalog) ~= "table"
            or type(catalog.resolver) ~= "table"
            or type(catalog.resolver.resolve) ~= "function"
            or type(catalog.resolver.verify_target) ~= "function"
            or type(catalog.path) ~= "table"
            or type(catalog.path.to_logical) ~= "function"
            or type(catalog.path.from_logical) ~= "function"
            or type(catalog.path.parent) ~= "function"
            or type(catalog.path.comparison_key) ~= "function"
            or type(components.publication) ~= "table"
            or type(components.publication.open_existing) ~= "function"
            or type(components.publication.turn_context) ~= "function"
        then
            return nil, failure(
                "InvalidBootstrapComponents",
                "existing Context catalog and publication ports are incomplete"
            )
        end
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
        ["continue"] = { id = true, selector = true },
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
    if request.id == "context-repl"
        and request.view ~= "recent"
        and request.view ~= "full"
    then
        return nil, failure("UsageError", "context-repl view must be recent or full")
    end
    if request.id == "continue"
        and (type(request.selector) ~= "string" or request.selector == "")
    then
        return nil, failure("UsageError", "continue requires one Context selector")
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

    local function load_config(overrides)
        local called, generation, config_error
        if overrides == nil then
            called, generation, config_error = pcall(
                admitted_components.config.reload_file,
                admitted.config_path
            )
        else
            called, generation, config_error = pcall(
                admitted_components.config.reload_file,
                admitted.config_path,
                overrides
            )
        end
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
        }, admitted_components.publication)
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

    local function context_call(callable, code, message, ...)
        local called, value, value_error = pcall(callable, ...)
        if not called then return nil, failure(code, message .. " raised an exception") end
        if value == nil then return nil, value_error or failure(code, message .. " failed") end
        return value, value_error
    end

    local function context_selection_error(selection)
        local tag = type(selection) == "table" and selection.tag or nil
        if tag == "InvalidSelector" then
            return failure(
                "UsageError",
                "the Context selector is invalid",
                "Use an exact Context name or canonical 16-hex hash."
            )
        end
        local messages = {
            NotFound = "no matching Context was found",
            HashCollision = "the Context hash matches multiple paths",
            MatchedUnavailable = "the matching Context is unavailable",
            ScanIncomplete = "the Context catalog scan is incomplete",
        }
        if messages[tag] then return failure(tag, messages[tag]) end
        return failure(
            "ContextSelectionFailure",
            "Context selection returned an invalid result"
        )
    end

    local function workspace_identity_equal(left, right)
        return type(left) == "table"
            and type(right) == "table"
            and left.kind == right.kind
            and left.volume == right.volume
            and left.object == right.object
    end

    local function dispatch_continue(request, preview_only)
        if not preview_only and active_draft then
            return nil, failure("SessionActive", "this process already owns an active chat")
        end
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local catalog = admitted_components.context_catalog
        if not catalog then
            return nil, failure(
                "ContextUnavailable",
                "existing Context services are unavailable on this invocation"
            )
        end
        local inspected, workspace, workspace_error = pcall(
            admitted_components.workspace.inspect,
            "."
        )
        if not inspected or not workspace then
            return nil, workspace_error or failure(
                "InvalidWorkspace",
                "the current workspace could not be inspected"
            )
        end
        local platform_kind = identity.os == "windows" and "windows" or "posix"
        local origin_logical, origin_error = context_call(
            catalog.path.to_logical,
            "UnsupportedPath",
            "current workspace path conversion",
            workspace.path
        )
        if not origin_logical then return nil, origin_error end
        local selection, selection_error = context_call(
            catalog.resolver.resolve,
            "ContextSelectionFailure",
            "Context selection",
            request.selector,
            origin_logical
        )
        if not selection then return nil, selection_error end
        if selection.tag ~= "Unique" then
            return nil, context_selection_error(selection)
        end
        local verified, verify_error = context_call(
            catalog.resolver.verify_target,
            "ContextTargetVerificationFailure",
            "Context target verification",
            selection,
            "open"
        )
        if not verified then return nil, verify_error end
        if verified.tag ~= "Verified" then
            local code = verified.tag == "TargetChanged"
                and "TargetChanged" or "MatchedUnavailable"
            return nil, failure(
                code,
                verified.tag == "TargetChanged"
                    and "the selected Context changed before it could be opened"
                    or "the selected Context is unavailable"
            )
        end
        if type(verified.logical_path) ~= "string"
            or type(verified.physical_hint) ~= "string"
            or type(verified.hash) ~= "string"
            or not verified.hash:match("^[0-9A-F][0-9A-F]+$")
            or #verified.hash ~= 16
            or type(verified.credential) ~= "table"
        then
            return nil, failure(
                "ContextTargetVerificationFailure",
                "Context target verification returned an incomplete credential"
            )
        end
        local recorded_logical, parent_error = context_call(
            catalog.path.parent,
            "UnsupportedPath",
            "recorded workspace derivation",
            verified.logical_path
        )
        if not recorded_logical then return nil, parent_error end
        local recorded_path, path_error = context_call(
            catalog.path.from_logical,
            "UnsupportedPath",
            "recorded workspace path conversion",
            recorded_logical,
            platform_kind
        )
        if not recorded_path then return nil, path_error end
        local recorded_called, recorded_workspace, recorded_workspace_error = pcall(
            admitted_components.workspace.inspect,
            recorded_path
        )
        if not recorded_called or not recorded_workspace then
            return nil, recorded_workspace_error or failure(
                "InvalidWorkspace",
                "the Context's recorded workspace is not enterable"
            )
        end
        local observed_recorded_logical, observed_error = context_call(
            catalog.path.to_logical,
            "UnsupportedPath",
            "recorded workspace verification",
            recorded_workspace.path
        )
        if not observed_recorded_logical then return nil, observed_error end
        local expected_key, expected_error = context_call(
            catalog.path.comparison_key,
            "UnsupportedPath",
            "recorded workspace comparison",
            recorded_logical,
            platform_kind
        )
        if not expected_key then return nil, expected_error end
        local observed_key, key_error = context_call(
            catalog.path.comparison_key,
            "UnsupportedPath",
            "observed workspace comparison",
            observed_recorded_logical,
            platform_kind
        )
        if not observed_key then return nil, key_error end
        if observed_key ~= expected_key then
            return nil, failure(
                "TargetChanged",
                "the Context's recorded workspace changed during verification"
            )
        end
        local origin_key, origin_key_error = context_call(
            catalog.path.comparison_key,
            "UnsupportedPath",
            "current workspace comparison",
            origin_logical,
            platform_kind
        )
        if not origin_key then return nil, origin_key_error end
        if origin_key ~= expected_key
            or not workspace_identity_equal(workspace.identity, recorded_workspace.identity)
        then
            return nil, failure(
                "WorkspaceConfirmationRequired",
                "the selected Context belongs to another workspace; run continue from "
                    .. recorded_path,
                "Run --continue from the recorded workspace: " .. recorded_path
            )
        end

        if preview_only then
            return readonly({
                kind = "continue-preview",
                selector = request.selector,
                logical_path = verified.logical_path,
                context_hash = verified.hash,
                recorded_workspace = recorded_workspace.path,
            }, "existing Context continuation preview")
        end

        local receipt, open_error = context_call(
            admitted_components.publication.open_existing,
            "ContextOpenUnknown",
            "existing Context open",
            {
                context_path = verified.physical_hint,
                logical_path = verified.logical_path,
                expected_credential = verified.credential,
            }
        )
        if not receipt then return nil, open_error end
        local released = false
        local function release_opened(primary_error)
            if released then return nil, primary_error end
            released = true
            local called, closed, close_error = pcall(
                admitted_components.publication.close
            )
            if not called or not closed then
                return nil, failure(
                    "ContextLeaseUnknown",
                    "existing Context writer release is unknown",
                    type(close_error) == "table" and close_error.code or nil
                )
            end
            return nil, primary_error
        end
        if type(receipt) ~= "table"
            or receipt.durable ~= true
            or receipt.context_path ~= verified.physical_hint
            or receipt.logical_path ~= verified.logical_path
            or receipt.context_hash ~= verified.hash
            or type(receipt.display_name) ~= "string"
            or not valid_integer(receipt.generation, 1)
            or not valid_integer(receipt.event_count, 0)
            or receipt.last_sequence ~= receipt.event_count
            or type(receipt.view_manifest_snapshot) ~= "string"
            or receipt.view_manifest_snapshot == ""
            or type(receipt.runtime_initial_serials) ~= "table"
        then
            return release_opened(failure(
                "ContextOpenUnknown",
                "existing Context open returned an incomplete durable receipt"
            ))
        end
        if receipt.auto_continue ~= true then
            return release_opened(failure(
                "ContextRecoveryRequired",
                "the selected Context has unresolved or unfinished durable work",
                "Inspect and resolve the Context before continuing it."
            ))
        end
        local turn_context, turn_error = context_call(
            admitted_components.publication.turn_context,
            "ContextTurnUnavailable",
            "durable Context turn snapshot",
            { expected_context_generation = receipt.generation }
        )
        if not turn_context then return release_opened(turn_error) end
        if type(turn_context) ~= "table" or type(turn_context.overrides) ~= "table"
            or turn_context.context_generation ~= receipt.generation
        then
            return release_opened(failure(
                "ContextTurnUnavailable",
                "durable Context turn snapshot is incomplete"
            ))
        end
        local generation, config_error = load_config(turn_context.overrides)
        if not generation then return release_opened(config_error) end
        if generation.agent_ready ~= true then
            return release_opened(failure(
                "ModelUnavailable",
                "the Context's selected Model cannot start the Agent"
            ))
        end
        local self_test_ok, self_test_error = run_startup_self_test(generation)
        if not self_test_ok then return release_opened(self_test_error) end

        local status = readonly({
            lifecycle = "saved",
            durable = true,
            context_path = receipt.context_path,
            logical_path = receipt.logical_path,
            context_hash = receipt.context_hash,
            display_name = receipt.display_name,
            workspace = recorded_workspace.path,
            config_generation = generation.id,
            model = generation.current_model,
            permission = generation.current_permission,
            double_check = generation.effective_double_check,
            double_check_goal = generation.effective_double_check_goal or "",
            context_prompt = generation.context_prompt or "",
            auto_rename_disabled = generation.auto_rename_disabled == true,
        }, "opened session status")
        local close_failure
        local draft = {}
        function draft.status() return status end
        function draft.config_generation() return generation end
        function draft.open_receipt() return receipt end
        function draft.close()
            if released then
                if close_failure then return nil, close_failure end
                return false
            end
            released = true
            local called, closed, close_error = pcall(
                admitted_components.publication.close
            )
            if not called or not closed then
                close_failure = close_error or failure(
                    "ContextLeaseUnknown",
                    "existing Context writer could not be released"
                )
                return nil, close_failure
            end
            return true
        end
        draft = readonly(draft, "opened session")
        active_draft = draft
        lifecycle = "context-ready"
        return readonly({
            kind = "continue-chat",
            outcome = "ready",
            draft = draft,
            status = status,
            open_receipt = receipt,
        }, "existing chat bootstrap result")
    end


    ---Resolves and reverifies one continuation target without acquiring its
    -- writer. This is the first phase of an in-chat Context switch; the later
    -- open must use the returned precise hash and repeat all verification.
    function application.preview_continue(selector)
        if lifecycle == "closed" then
            return nil, failure("ApplicationClosed", "the application lifecycle is closed")
        end
        if type(selector) ~= "string" or selector == "" then
            return nil, failure("UsageError", "continue preview requires one Context selector")
        end
        return dispatch_continue({ id = "continue", selector = selector }, true)
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
                    "context-repl", "continue", "run-chat",
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
        if request.id == "continue" then return dispatch_continue(request) end
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
        local closed_draft, close_error = true, nil
        if active_draft then
            closed_draft, close_error = active_draft.close()
        end
        active_draft = nil
        lifecycle = "closed"
        if not closed_draft then return nil, close_error end
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
        maximum_output_bytes = 40 * 1024 * 1024,
        maximum_poll_bytes = 65536,
    },
    terminal = { maximum_input_bytes = 65536 },
}

local CONTEXT_INDEX_OPTIONS = {
    maximum_scan_candidates = 10000,
    maximum_search_rings = 256,
    maximum_collision_candidates = 64,
    maximum_reason_bytes = 128,
}

local CONTEXT_SCANNER_OPTIONS = {
    maximum_walk_depth = 256,
    maximum_walk_entries = 10000,
}

local CONTEXT_BROWSER_PAGE_LIMIT = 100
local CONTEXT_RECENT_DEFAULT_LIMIT = 20

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

local MODEL_ADAPTER_OPTIONS = {
    maximum_json_bytes = 1024 * 1024,
    maximum_json_depth = 32,
    maximum_json_nodes = 16384,
    maximum_string_bytes = 262144,
    maximum_number_bytes = 64,
    maximum_sse_line_bytes = 65536,
    maximum_sse_event_bytes = 262144,
    maximum_sse_buffered_bytes = 512 * 1024,
    maximum_sse_events_per_push = 256,
    maximum_response_bytes = 16 * 1024 * 1024,
    maximum_text_bytes = 65536,
    maximum_reasoning_bytes = 65536,
    maximum_tool_calls = 64,
    maximum_tool_argument_bytes = 32768,
    maximum_total_tool_argument_bytes = 262144,
    maximum_content_blocks = 256,
    maximum_events = 512,
}

local MODEL_ACTIVITY_OPTIONS = {
    maximum_poll_events = 128,
    maximum_queued_events = 1024,
    maximum_header_bytes = 262144,
    maximum_header_line_bytes = 16384,
    maximum_header_lines = 1024,
    maximum_redirects = 3,
    maximum_turn_time_ms = 3600000,
    maximum_runtime_time_ms = 3600000,
    maximum_canonical_body_bytes = 65536,
    retry_manifest = {
        identity = "tp006-modern-candidate-v1",
        maximum_count = 10,
        exponent = 2,
        maximum_delay_ms = 30000,
        runtime_wait_cap_ms = 60000,
        deterministic_jitter_permille = 100,
    },
}

-- These are release-owned candidate caps. C32 may only tighten/calibrate them
-- per target; ordinary configuration cannot raise them.
local AGENT_RELEASE_OPTIONS = {
    permission = {
        maximum_name_bytes = 128,
        maximum_generation_bytes = 256,
        maximum_arguments_bytes = 65536,
        maximum_target_bytes = 32768,
        maximum_identity_bytes = 65536,
        maximum_prompt_bytes = 32768,
    },
    operation = {
        maximum_identifier_bytes = 256,
        maximum_evidence_bytes = 17 * 1024 * 1024,
        unresolved_operation_ids = {},
    },
    json = {
        maximum_bytes = 1024 * 1024,
        maximum_depth = 32,
        maximum_nodes = 16384,
        maximum_string_bytes = 262144,
        maximum_number_bytes = 64,
    },
    driver = {
        model_poll_events = 128,
        tool_poll_events = 128,
        review_poll_events = 128,
        maximum_output_events = 512,
    },
    runtime = {
        hard_caps = {
            active_time_ms = 3600000,
            model_requests = 64,
            tool_calls = 256,
            reviews = 64,
            steps = 512,
            message_bytes = 262144,
            result_bytes = 16 * 1024 * 1024,
        },
        stuck = {
            snapshot_id = "tp017-modern-candidate-v1",
            exact_repeat = 3,
            same_error = 3,
            abab_cycle = 2,
            semantic_no_progress = 4,
            runtime_maximum = 16,
        },
        initial_sequence = 2,
        initial_context_generation = 1,
        initial_view_manifest_ref = false,
        initial_serials = {
            turn = 0,
            message = 0,
            request = 0,
            tool = 0,
            operation = 0,
            queue = 0,
            queue_display = 0,
            side = 0,
        },
        automatic_compaction = true,
        maximum_identifier_bytes = 256,
        hard_cap_snapshot_id = "tp017-modern-candidate-v1",
        lanes = {
            queue_maximum = 9,
            side_active_time_ms = 120000,
            side_response_bytes = 65536,
            side_snapshot_id = "tp022-modern-candidate-v1",
        },
    },
}

local CONTINUATION_INSTRUCTION = table.concat({
    "Continue from the latest durable Context facts.",
    " Treat those facts as the canonical conversation and tool history.",
    " Use a typed control when the current turn has a reportable outcome.",
})

local function production_clock(backend)
    return readonly({
        now = backend.clock_port.monotonic_now,
    }, "production Agent clock")
end

local function permission_matrix(configured)
    if type(configured) ~= "table" then return nil end
    return {
        Read = configured.read,
        Write = configured.write,
        Delete = configured.delete,
        Shell = configured.shell,
        OutsideWorkspace = configured.outside_workspace,
    }
end

local function workspace_identity_key(identity)
    if type(identity) ~= "table"
        or type(identity.volume) ~= "string"
        or type(identity.object) ~= "string"
        or type(identity.kind) ~= "string"
    then
        return nil
    end
    return identity.volume .. "\0" .. identity.object .. "\0" .. identity.kind
end

local function tool_authorization_port(safety_service, expected)
    local function authority_digest(call, facts)
        if type(call) ~= "table"
            or type(call.call_digest) ~= "string"
            or type(facts) ~= "table"
            or facts.permission_snapshot_digest ~= expected.permission_snapshot_digest
            or facts.config_generation ~= expected.config_generation
            or facts.workspace_identity ~= expected.workspace_identity
            or facts.double_check ~= expected.double_check
            or type(facts.approval_digest) ~= "string"
            or type(facts.durable_intent_digest) ~= "string"
            or (facts.action_review ~= "not-required"
                and facts.action_review ~= "approved"
                and facts.action_review ~= "tightened")
        then
            return nil
        end
        return safety_service.binding_digest("yaca-tool-authority-v1", {
            { name = "call_digest", value = call.call_digest },
            {
                name = "permission_snapshot_digest",
                value = facts.permission_snapshot_digest,
            },
            { name = "approval_digest", value = facts.approval_digest },
            { name = "durable_intent_digest", value = facts.durable_intent_digest },
            { name = "config_generation", value = facts.config_generation },
            { name = "workspace_identity", value = facts.workspace_identity },
            { name = "double_check", value = tostring(facts.double_check) },
            { name = "action_review", value = facts.action_review },
        })
    end
    return readonly({
        admit = function(call, facts)
            local digest = authority_digest(call, facts)
            if not digest then return false end
            return true, digest
        end,
        reverify = function(call, facts, digest)
            local current = authority_digest(call, facts)
            return current ~= nil and current == digest
        end,
    }, "production Tool authorization")
end

local function tool_options(composed, generation, workspace_path)
    local output_limit = (generation.exec.max_output_kb or 1024) * 1024
    local deadline = generation.exec.timeout_ms or 3600000
    return {
        maximum_argument_bytes = 65536,
        maximum_path_bytes = 32768,
        maximum_content_bytes = 32768,
        maximum_file_bytes = 16 * 1024 * 1024,
        maximum_result_bytes = AGENT_RELEASE_OPTIONS.runtime.hard_caps.result_bytes,
        maximum_list_depth = 8,
        maximum_page_entries = 256,
        maximum_walk_entries = 10000,
        maximum_search_pattern_bytes = 4096,
        maximum_search_matches = 1000,
        maximum_patch_hunks = 256,
        maximum_patch_lines = 4096,
        maximum_line_bytes = 32768,
        maximum_continuations = 64,
        maximum_identifier_bytes = 256,
        filesystem_chunk_bytes = 65536,
        create_permissions = 384,
        maximum_json_depth = 32,
        maximum_json_nodes = 16384,
        maximum_number_bytes = 64,
        maximum_exec_output_bytes = output_limit,
        maximum_exec_deadline_ms = deadline,
        platform_kind = composed.identity.os == "windows" and "windows" or "posix",
        workspace_path = workspace_path,
        reserved_paths = { composed.layout.data_root },
    }
end

local function runtime_options()
    local candidate = copy_plain(AGENT_RELEASE_OPTIONS.runtime, {})
    if not candidate then return nil end
    return candidate
end

local function scoped_model_activity_options(composed, context_hash, side)
    if type(context_hash) ~= "string"
        or context_hash == ""
        or #context_hash > 64
        or not context_hash:match("^[0-9A-F]+$")
    then
        return nil, failure(
            "InvalidContextIdentity",
            "Model activities require the exact durable Context hash"
        )
    end
    local candidate = copy_plain(composed.model_activity_options, {})
    if not candidate then
        return nil, failure(
            "InvalidModelActivity",
            "Model activity limits could not be copied"
        )
    end
    candidate.identity_namespace = "context-" .. context_hash
    if side then
        candidate.maximum_turn_time_ms = math.min(
            candidate.maximum_turn_time_ms,
            AGENT_RELEASE_OPTIONS.runtime.lanes.side_active_time_ms
        )
        candidate.maximum_canonical_body_bytes = math.min(
            candidate.maximum_canonical_body_bytes,
            AGENT_RELEASE_OPTIONS.runtime.lanes.side_response_bytes
        )
    end
    return readonly(candidate, "Context-scoped Model activity options")
end

local function build_turn_ports(composed, shared, turn)
    local generation = turn.generation
    local contexts = composed.contexts
    local permission_module = require("permission")
    local permission_service, permission_error = permission_module.new({
        safety = contexts.safety,
    }, AGENT_RELEASE_OPTIONS.permission)
    if not permission_service then return nil, permission_error end
    local configured_permission = generation.permissions[turn.permission]
    local matrix = permission_matrix(configured_permission)
    if not matrix then
        return nil, failure(
            "PermissionUnavailable",
            "the selected Permission generation is unavailable"
        )
    end
    local profile, profile_error = permission_service:profile({
        name = turn.permission,
        config_generation = generation.id,
        matrix = matrix,
        description = configured_permission.description,
        system_prompt = configured_permission.system_prompt,
    })
    if not profile then return nil, profile_error end

    local inspected, workspace = composed.backend.filesystem.direct_inspect(
        turn.workspace
    )
    local workspace_key = inspected and workspace_identity_key(workspace.identity) or nil
    if not inspected or not workspace_key then
        return nil, inspected and failure(
            "InvalidWorkspace",
            "the durable workspace identity is unavailable to direct Tools"
        ) or workspace
    end
    local authorization = tool_authorization_port(contexts.safety, {
        permission_snapshot_digest = profile.snapshot_digest,
        config_generation = generation.id,
        workspace_identity = workspace_key,
        double_check = turn.double_check,
    })
    local secret_registry = readonly({
        scan = generation.scan_registered_secrets,
        new_stream_scanner = generation.new_stream_scanner,
    }, "turn secret scanner")
    local tools_module = require("tools")
    local tool_service, tool_error = tools_module.new({
        filesystem = composed.backend.filesystem,
        path = contexts.path,
        safety = contexts.safety,
        secret_registry = secret_registry,
        authorization = authorization,
        processes = composed.backend.processes,
        operations = shared.operations,
    }, tool_options(composed, generation, turn.workspace))
    if not tool_service then return nil, tool_error end
    if tool_service.registry_digest ~= turn.tool_registry_snapshot then
        return nil, failure(
            "ToolRegistryMismatch",
            "the production Tool registry does not match the durable turn snapshot"
        )
    end
    local tool_port, tool_port_error = tools_module.new_agent_port({
        service = tool_service,
        permission = permission_service,
        profile = profile,
        operation_journal = shared.operation_journal,
        clock = shared.clock,
    }, {
        config_generation = generation.id,
        double_check = turn.double_check,
        action_review_enabled = generation.agent.action_review_enabled,
        exec_policy = {
            config_generation = generation.id,
            environment_mode = generation.exec.environment_mode,
            environment = {},
            output_limit_bytes = (generation.exec.max_output_kb or 1024) * 1024,
            deadline_ms = generation.exec.timeout_ms or 3600000,
            decoder = "utf-8-strict-candidate-v1",
        },
    })
    if not tool_port then return nil, tool_port_error end

    local model_module = require("model")
    local activity_options, activity_options_error = scoped_model_activity_options(
        composed,
        turn.context_hash,
        false
    )
    if not activity_options then return nil, activity_options_error end
    local views = readonly({
        resolve_view = composed.publication.resolve_view,
    }, "active durable Model views")
    local request_builder, builder_error = model_module.new_request_builder({
        adapter = composed.model_adapter,
        prompt = contexts.prompt,
        views = views,
        generation = generation,
        tool_registry = contexts.tool_registry,
    }, {
        model_name = turn.model,
        permission_name = turn.permission,
        model_snapshot = turn.model_snapshot,
        permission_snapshot = turn.permission_snapshot,
        prompt_snapshot = turn.prompt_snapshot,
        tool_registry_snapshot = turn.tool_registry_snapshot,
        initial_message = turn.initial_message,
        context_prompt = turn.context_prompt,
        continuation_instruction = CONTINUATION_INSTRUCTION,
        default_connect_timeout_ms = 120000,
        default_request_timeout_ms = 3600000,
        default_retry_base_delay_ms = 1000,
        default_max_output_tokens = 4096,
    })
    if not request_builder then return nil, builder_error end
    local model_activity, model_activity_error = model_module.new_activity({
        adapter = composed.model_adapter,
        transport = composed.network,
        safety = contexts.safety,
        clock = composed.backend.clock_port,
        requests = request_builder,
    }, activity_options)
    if not model_activity then return nil, model_activity_error end

    local compaction_builder, compaction_builder_error
        = model_module.new_compaction_request_builder({
            adapter = composed.model_adapter,
            prompt = contexts.prompt,
            generation = generation,
            codec = shared.codec,
            safety = contexts.safety,
        }, {
            model_name = turn.model,
            permission_name = turn.permission,
            config_snapshot = turn.config_snapshot,
            model_snapshot = turn.model_snapshot,
            prompt_snapshot = turn.prompt_snapshot,
            context_prompt = turn.context_prompt,
            default_connect_timeout_ms = 120000,
            default_request_timeout_ms = 3600000,
            default_retry_base_delay_ms = 1000,
            default_max_output_tokens = 4096,
            maximum_source_bytes = 16 * 1024 * 1024,
            maximum_summary_bytes = 65536,
            maximum_correction_bytes = 65536,
        })
    if not compaction_builder then return nil, compaction_builder_error end
    local compaction_activity, compaction_activity_error = model_module.new_activity({
        adapter = composed.model_adapter,
        transport = composed.network,
        safety = contexts.safety,
        clock = composed.backend.clock_port,
        requests = compaction_builder,
    }, activity_options)
    if not compaction_activity then return nil, compaction_activity_error end
    local compaction_model, compaction_model_error = model_module.new_compaction_port({
        activity = compaction_activity,
        builder = compaction_builder,
        safety = contexts.safety,
        codec = shared.codec,
        summary = readonly({
            encode = compact.encode_summary,
        }, "structured compaction summary encoder"),
    }, {
        maximum_poll_events = 128,
        maximum_summary_bytes = 65536,
    })
    if not compaction_model then return nil, compaction_model_error end

    local review_builder, review_builder_error = model_module.new_review_request_builder({
        adapter = composed.model_adapter,
        prompt = contexts.prompt,
        views = views,
        generation = generation,
        codec = shared.codec,
        safety = contexts.safety,
    }, {
        main_model_name = turn.model,
        permission_name = turn.permission,
        config_snapshot = turn.config_snapshot,
        context_prompt = turn.context_prompt,
        default_connect_timeout_ms = 120000,
        default_request_timeout_ms = 3600000,
        default_retry_base_delay_ms = 1000,
        default_max_output_tokens = 1024,
        maximum_binding_bytes = 65536,
    })
    if not review_builder then return nil, review_builder_error end
    local review_activity, review_activity_error = model_module.new_activity({
        adapter = composed.model_adapter,
        transport = composed.network,
        safety = contexts.safety,
        clock = composed.backend.clock_port,
        requests = review_builder,
    }, activity_options)
    if not review_activity then return nil, review_activity_error end
    local review_port, review_port_error = model_module.new_review_port({
        activity = review_activity,
        builder = review_builder,
        safety = contexts.safety,
        codec = shared.codec,
    }, {
        maximum_poll_events = 128,
        maximum_reason_bytes = 32768,
        maximum_gap_bytes = 32768,
    })
    if not review_port then return nil, review_port_error end

    return {
        generation = generation,
        model = model_activity,
        tools = tool_port,
        reviews = review_port,
        compaction = compaction_model,
        compaction_binding = readonly({
            generation_id = generation.id,
            model_name = turn.model,
            permission_name = turn.permission,
            config_snapshot = turn.config_snapshot,
            model_snapshot = turn.model_snapshot,
            prompt_snapshot = turn.prompt_snapshot,
            context_prompt = turn.context_prompt,
        }, "generation-bound compaction binding"),
    }
end

local function build_side_activity(composed, side)
    local model_module = require("model")
    local views = readonly({
        resolve_view = composed.publication.resolve_view,
    }, "durable side Model views")
    local request_builder, builder_error = model_module.new_side_request_builder({
        adapter = composed.model_adapter,
        prompt = composed.contexts.prompt,
        views = views,
        generation = side.generation,
        tool_registry = composed.contexts.tool_registry,
        safety = composed.contexts.safety,
    }, {
        model_name = side.model,
        permission_name = side.permission,
        model_snapshot = side.model_snapshot,
        permission_snapshot = side.permission_snapshot,
        prompt_snapshot = side.prompt_snapshot,
        tool_registry_snapshot = side.tool_registry_snapshot,
        initial_message = side.initial_message,
        context_prompt = side.context_prompt,
        default_connect_timeout_ms = 120000,
        maximum_request_time_ms = AGENT_RELEASE_OPTIONS.runtime.lanes.side_active_time_ms,
        default_retry_base_delay_ms = 1000,
        maximum_output_tokens = 1024,
    })
    if not request_builder then return nil, builder_error end
    local activity_options, activity_options_error = scoped_model_activity_options(
        composed,
        side.context_hash,
        true
    )
    if not activity_options then return nil, activity_options_error end
    local activity, activity_error = model_module.new_activity({
        adapter = composed.model_adapter,
        transport = composed.network,
        safety = composed.contexts.safety,
        clock = composed.backend.clock_port,
        requests = request_builder,
    }, activity_options)
    if not activity then return nil, activity_error end
    return {
        generation = side.generation,
        view_manifest_ref = side.view_manifest_ref,
        activity = activity,
    }
end

local SIDE_RUNTIME_REQUEST_FIELDS = {
    side_id = true,
    turn_id = true,
    request_id = true,
    purpose = true,
    view_manifest_ref = true,
    no_tools = true,
    active_time_cap_ms = true,
    response_byte_cap = true,
    budget_snapshot_id = true,
}

local function new_side_catalog()
    local prepared = false
    local current = false
    local catalog = {}

    local function idle_activity(candidate)
        if not candidate then return true end
        local called, status = pcall(candidate.activity.status)
        return called and type(status) == "table" and status.state == "idle"
    end

    function catalog.idle()
        return idle_activity(prepared) and idle_activity(current)
    end

    function catalog.prepare(candidate)
        if type(candidate) ~= "table"
            or type(candidate.generation) ~= "table"
            or type(candidate.view_manifest_ref) ~= "string"
            or type(candidate.activity) ~= "table"
            or type(candidate.activity.start) ~= "function"
            or type(candidate.activity.cancel) ~= "function"
            or type(candidate.activity.poll) ~= "function"
            or type(candidate.activity.status) ~= "function"
        then
            return nil, failure(
                "InvalidSideActivity",
                "prepared side Model activity is incomplete"
            )
        end
        if not catalog.idle() then
            return nil, failure(
                "SideActivityBusy",
                "a side Model activity is already active"
            )
        end
        prepared = candidate
        return true
    end

    function catalog.start(specification)
        if type(specification) ~= "table" or not prepared then
            return nil, failure(
                "SideActivityUnavailable",
                "the frozen side Model activity is unavailable"
            )
        end
        for key in pairs(specification) do
            if type(key) ~= "string" or not SIDE_RUNTIME_REQUEST_FIELDS[key] then
                return nil, failure(
                    "InvalidSideActivity",
                    "side Runtime request is ambiguous"
                )
            end
        end
        for key in pairs(SIDE_RUNTIME_REQUEST_FIELDS) do
            if specification[key] == nil then
                return nil, failure(
                    "InvalidSideActivity",
                    "side Runtime request is incomplete"
                )
            end
        end
        if specification.purpose ~= "side"
            or specification.no_tools ~= true
            or specification.side_id ~= specification.turn_id
            or specification.view_manifest_ref ~= prepared.view_manifest_ref
            or specification.active_time_cap_ms
                ~= AGENT_RELEASE_OPTIONS.runtime.lanes.side_active_time_ms
            or specification.response_byte_cap
                ~= AGENT_RELEASE_OPTIONS.runtime.lanes.side_response_bytes
            or specification.budget_snapshot_id
                ~= AGENT_RELEASE_OPTIONS.runtime.lanes.side_snapshot_id
        then
            return nil, failure(
                "InvalidSideActivity",
                "side Runtime request contradicts its frozen release snapshot"
            )
        end
        local handle, start_error = prepared.activity.start({
            request_id = specification.request_id,
            turn_id = specification.turn_id,
            purpose = "side",
            continuation = false,
            view_manifest_ref = specification.view_manifest_ref,
            progress_identity = "side:" .. specification.side_id,
        })
        if not handle then return nil, start_error end
        current = prepared
        prepared = false
        return handle
    end

    function catalog.cancel(handle, reason)
        if not current then return { outcome = "unknown" } end
        return current.activity.cancel(handle, reason)
    end

    function catalog.poll(budget)
        if not current then return {} end
        return current.activity.poll(budget)
    end

    function catalog.status()
        if current then return current.activity.status() end
        if prepared then return readonly({
            state = "prepared",
            generation = prepared.generation.id,
        }, "prepared side activity status") end
        return readonly({ state = "idle" }, "side activity status")
    end

    function catalog.generation()
        local candidate = prepared or current
        return candidate and candidate.generation or false
    end

    return readonly(catalog, "production side activity catalog")
end

local function new_turn_catalog(initial)
    local current = initial
    local function invoke(domain, method, ...)
        return current[domain][method](...)
    end
    local model = readonly({
        start = function(...) return invoke("model", "start", ...) end,
        cancel = function(...) return invoke("model", "cancel", ...) end,
        poll = function(...) return invoke("model", "poll", ...) end,
        status = function(...) return invoke("model", "status", ...) end,
    }, "generation-bound Model port")
    local tools = readonly({
        admit = function(...) return invoke("tools", "admit", ...) end,
        start = function(...) return invoke("tools", "start", ...) end,
        cancel = function(...) return invoke("tools", "cancel", ...) end,
        poll = function(...) return invoke("tools", "poll", ...) end,
        prepare_approval = function(...)
            return invoke("tools", "prepare_approval", ...)
        end,
        record_approval = function(...)
            return invoke("tools", "record_approval", ...)
        end,
        active_handle = function(...) return invoke("tools", "active_handle", ...) end,
    }, "generation-bound Tool port")
    local reviews = readonly({
        start = function(...) return invoke("reviews", "start", ...) end,
        cancel = function(...) return invoke("reviews", "cancel", ...) end,
        poll = function(...) return invoke("reviews", "poll", ...) end,
        status = function(...) return invoke("reviews", "status", ...) end,
    }, "generation-bound review port")
    local compaction = readonly({
        start = function(...) return invoke("compaction", "start", ...) end,
        cancel = function(...) return invoke("compaction", "cancel", ...) end,
        poll = function(...) return invoke("compaction", "poll", ...) end,
        status = function(...) return invoke("compaction", "status", ...) end,
    }, "generation-bound compaction Model port")
    local catalog = {}

    function catalog.idle()
        local model_ok, model_status = pcall(current.model.status)
        local review_ok, review_status = pcall(current.reviews.status)
        local compact_ok, compact_status = pcall(current.compaction.status)
        local tool_ok, tool_handle = pcall(current.tools.active_handle)
        return model_ok and type(model_status) == "table" and model_status.state == "idle"
            and review_ok and type(review_status) == "table" and review_status.state == "idle"
            and compact_ok and type(compact_status) == "table"
            and compact_status.state == "idle"
            and tool_ok and tool_handle == false
    end

    function catalog.replace(candidate)
        if not catalog.idle() then
            return nil, failure(
                "TurnActivitiesBusy",
                "a new generation cannot replace active turn activities"
            )
        end
        if type(candidate) ~= "table"
            or type(candidate.generation) ~= "table"
            or type(candidate.compaction) ~= "table"
            or type(candidate.compaction.start) ~= "function"
            or type(candidate.compaction.cancel) ~= "function"
            or type(candidate.compaction.poll) ~= "function"
            or type(candidate.compaction.status) ~= "function"
            or type(candidate.compaction_binding) ~= "table"
        then
            return nil, failure(
                "InvalidTurnActivities",
                "replacement generation omits its compaction Model port"
            )
        end
        current = candidate
        return true
    end

    function catalog.generation()
        return current.generation
    end

    function catalog.compaction_binding()
        return current.compaction_binding
    end

    catalog.model = model
    catalog.tools = tools
    catalog.reviews = reviews
    catalog.compaction = compaction
    return readonly(catalog, "production turn catalog")
end

local function compaction_prompt_upper_bound(generation, binding)
    local model = generation.models[binding.model_name]
    local permission = generation.permissions[binding.permission_name]
    if type(generation.general) ~= "table"
        or type(model) ~= "table"
        or type(permission) ~= "table"
    then
        return nil, failure(
            "CompactionSnapshotUnavailable",
            "compaction Prompt components are unavailable"
        )
    end
    local values = {
        generation.general.system_prompt,
        model.system_prompt,
        permission.system_prompt,
        binding.context_prompt,
    }
    local total = 4096
    for _, value in ipairs(values) do
        if type(value) ~= "string" then
            return nil, failure(
                "CompactionSnapshotUnavailable",
                "compaction Prompt component is not frozen text"
            )
        end
        total = total + #value
    end
    return total
end

local function compaction_options(
    generation,
    binding,
    initial_serial,
    initial_automatic_failure_count,
    automatic_failure_history_complete
)
    local model = generation.models[binding.model_name]
    local configured_threshold = generation.agent
        and generation.agent.compact_threshold
    if type(model) ~= "table"
        or not valid_integer(model.context_length, 1)
        or not valid_integer(initial_serial, 0)
        or not valid_integer(initial_automatic_failure_count, 0)
        or type(automatic_failure_history_complete) ~= "boolean"
        or (configured_threshold ~= false
            and (type(configured_threshold) ~= "number"
                or configured_threshold <= 0
                or configured_threshold > 1))
    then
        return nil, failure(
            "CompactionCapacityUnknown",
            "the current Model window or compaction threshold is unavailable"
        )
    end
    local threshold = configured_threshold == false and 0.75
        or configured_threshold
    local numerator = math.floor(threshold * 1000 + 0.5)
    if numerator < 1 then numerator = 1 end
    if numerator >= 1000 then numerator = 999 end
    local maximum_view_tokens = math.min(model.context_length, 262144)
    if maximum_view_tokens < 2 then
        return nil, failure(
            "CompactionCapacityUnknown",
            "the current Model window cannot admit a structured summary"
        )
    end
    local output_tokens = model.max_output_tokens or 4096
    output_tokens = math.min(output_tokens, 4096, maximum_view_tokens - 1)
    local failure_threshold = 3
    if not automatic_failure_history_complete then
        initial_automatic_failure_count = math.max(
            initial_automatic_failure_count,
            failure_threshold
        )
    end
    return {
        automatic_enabled = configured_threshold ~= false,
        output_tokens = output_tokens,
        service = {
            maximum_identifier_bytes = 256,
            initial_serial = initial_serial,
            initial_automatic_failure_count = initial_automatic_failure_count,
            manifest = {
                snapshot_id = "compaction-release-v1",
                builder_algorithm = "structured-prefix-v1",
                summary_schema = "1",
                maximum_events = 256,
                maximum_groups = 256,
                maximum_input_bytes = 16 * 1024 * 1024,
                maximum_summary_bytes = 65536,
                maximum_summary_tokens = output_tokens,
                maximum_view_tokens = maximum_view_tokens,
                maximum_attempts = 2,
                active_time_ms = 3600000,
                failure_threshold = failure_threshold,
                failure_cooldown_ms = 60000,
                trigger_numerator = numerator,
                trigger_denominator = 1000,
                reserve_tokens = math.min(2048, maximum_view_tokens - 1),
                minimum_benefit_tokens = math.min(256, maximum_view_tokens - 1),
            },
        },
    }
end

---Composes the current turn's no-tool compaction Model with the Context
-- journal and Runtime external-receipt gate. The owner is single-concurrency,
-- polls in bounded batches, and never derives completion from rendered text.
local function new_production_compaction(composed, catalog, loop, clock)
    if type(composed.publication.compaction_snapshot) ~= "function"
        or type(composed.publication.compaction_journal) ~= "function"
        or type(catalog.compaction_binding) ~= "function"
        or type(loop.begin_compaction) ~= "function"
        or type(loop.adopt_compaction_receipt) ~= "function"
        or type(loop.fail_compaction_barrier) ~= "function"
        or type(loop.finish_compaction) ~= "function"
    then
        return nil, failure(
            "InvalidCompactionComposition",
            "production compaction ports are incomplete"
        )
    end
    local durable_journal = composed.publication.compaction_journal()
    if type(durable_journal) ~= "table" then
        return nil, failure(
            "InvalidCompactionComposition",
            "durable compaction journal is unavailable"
        )
    end
    local service
    local service_generation = false
    local automatic_enabled = false
    local output_tokens = false
    local reserve_tokens = false
    local active = false
    local last_result = false
    local closed = false
    local owner = {}

    local function fail_compaction_barrier(reason, fallback)
        local _, barrier_error = loop:fail_compaction_barrier(reason)
        return false, barrier_error or fallback
    end

    local journal = {}
    for _, method in ipairs({
        "commit_intent", "commit_response", "commit_rejection",
        "publish", "commit_correction",
    }) do
        journal[method] = function(record)
            local called, committed, receipt = pcall(
                durable_journal[method],
                record
            )
            if not called or committed ~= true then
                return fail_compaction_barrier(
                    not called and "journal-exception" or "journal-rejected",
                    receipt
                )
            end
            local runtime_receipt = type(receipt) == "table"
                and receipt.runtime_receipt or nil
            local publishing = method == "publish"
            if type(runtime_receipt) ~= "table"
                or receipt.binding ~= record
                or receipt.previous_context_generation
                    ~= runtime_receipt.previous_context_generation
                or receipt.context_generation ~= runtime_receipt.context_generation
                or (publishing and (
                    receipt.previous_manifest_digest
                        ~= record.expected_manifest_digest
                    or type(record.manifest) ~= "table"
                    or receipt.published_manifest_digest ~= record.manifest.digest
                ))
                or (not publishing
                    and receipt.active_manifest_digest
                        ~= record.expected_manifest_digest)
            then
                return fail_compaction_barrier("receipt-contract", failure(
                    "CompactionJournalContract",
                    "durable compaction receipt omits its Runtime barrier"
                ))
            end
            local adoption_called, adopted, adoption_error = pcall(
                loop.adopt_compaction_receipt,
                loop,
                record,
                runtime_receipt
            )
            if not adoption_called then
                return fail_compaction_barrier("adoption-exception", adopted)
            end
            if not adopted then return false, adoption_error end
            return true, receipt
        end
    end
    journal = readonly(journal, "Runtime-adopting compaction journal")

    local function ensure_service(snapshot, binding)
        local generation = catalog.generation()
        if type(generation) ~= "table" or generation.id ~= binding.generation_id then
            return nil, failure(
                "CompactionSnapshotUnavailable",
                "current turn generation does not match its compaction binding"
            )
        end
        if service and service_generation == generation.id then return service end
        if service then
            local status = service:status()
            if status.state ~= "Idle" then
                return nil, failure(
                    "CompactionBusy",
                    "the prior compaction generation is not idle"
                )
            end
            service:close("compaction-generation-replaced")
        end
        local options, options_error = compaction_options(
            generation,
            binding,
            snapshot.initial_serial,
            snapshot.initial_automatic_failure_count,
            snapshot.automatic_failure_history_complete
        )
        if not options then return nil, options_error end
        local candidate, candidate_error = compact.new({
            safety = composed.contexts.safety,
            estimator = readonly({
                estimate = function(bytes)
                    if type(bytes) ~= "string" then
                        return nil, failure(
                            "CompactionEstimateFailure",
                            "token estimator requires exact bytes"
                        )
                    end
                    -- One token per input byte is deliberately conservative
                    -- across old targets and avoids a modern tokenizer runtime.
                    return #bytes
                end,
            }, "conservative compaction estimator"),
            clock = clock,
            model = catalog.compaction,
            journal = journal,
        }, options.service)
        if not candidate then return nil, candidate_error end
        service = candidate
        service_generation = generation.id
        automatic_enabled = options.automatic_enabled
        output_tokens = options.output_tokens
        reserve_tokens = options.service.manifest.reserve_tokens
        return service
    end

    local function observation()
        local status = loop:status()
        if type(status.active_view_manifest_ref) ~= "string"
            or status.active_view_manifest_ref == ""
        then
            return nil, failure(
                "CompactionSnapshotUnavailable",
                "Runtime has no active durable Model-view manifest"
            )
        end
        return status, readonly({
            expected_context_generation = status.context_generation,
            expected_last_sequence = status.last_durable_sequence,
            expected_manifest_digest = status.active_view_manifest_ref,
        }, "compaction Runtime observation")
    end

    local function build_input(mode)
        local status, observed = observation()
        if not status then return nil, observed end
        local snapshot, snapshot_error = composed.publication.compaction_snapshot(
            observed
        )
        if not snapshot then return nil, snapshot_error end
        if snapshot.binding ~= observed then
            return nil, failure(
                "CompactionSnapshotUnavailable",
                "Context did not acknowledge the exact Runtime observation"
            )
        end
        local binding = catalog.compaction_binding()
        local current, current_error = ensure_service(snapshot, binding)
        if not current then return nil, current_error end
        if mode == "automatic" and not automatic_enabled then
            return readonly({
                disabled = true,
                status = status,
                observation = observed,
                snapshot = snapshot,
            }, "disabled automatic compaction input")
        end
        local generation = catalog.generation()
        local model = generation.models[binding.model_name]
        local prompt_tokens, prompt_error = compaction_prompt_upper_bound(
            generation,
            binding
        )
        if not prompt_tokens then return nil, prompt_error end
        local active_estimated = snapshot.view_body_bytes + prompt_tokens
            + output_tokens + reserve_tokens
        return readonly({
            status = status,
            observation = observed,
            snapshot = snapshot,
            input = readonly({
                mode = mode,
                document = snapshot.document,
                expected_context_generation = snapshot.context_generation,
                expected_manifest_digest = snapshot.manifest_digest,
                context_digest = snapshot.context_digest,
                config_snapshot = binding.config_snapshot,
                model_snapshot = readonly({
                    id = binding.model_name,
                    digest = binding.model_snapshot,
                    window_tokens = model.context_length,
                    maximum_output_tokens = output_tokens,
                }, "frozen compaction Model snapshot"),
                prompt_bundle_digest = binding.prompt_snapshot,
                prompt_tokens = prompt_tokens,
                tool_schema_tokens = 0,
                control_schema_tokens = 0,
                main_state = status.state,
                active_view = readonly({
                    manifest_digest = snapshot.manifest_digest,
                    estimated_tokens = active_estimated,
                    builder_algorithm = "structured-prefix-v1",
                    summary_id = snapshot.manifest_compaction_id ~= false
                        and snapshot.manifest_compaction_id .. ":summary" or false,
                    included_ranges = snapshot.included_ranges,
                }, "active compaction Model-view snapshot"),
                corrections = snapshot.corrections,
            }, "production compaction input"),
        }, "bound production compaction input")
    end

    local function result_outcome(result)
        if type(result) ~= "table" then return nil end
        if type(result.outcome) == "string" then return result.outcome end
        if result.decision == "no_op" then return "no_op" end
        if result.decision == "fits" then return "fits" end
        if result.decision == "suppressed" then return "suppressed" end
        if result.decision == "waiting_user" then return "waiting_user" end
        return nil
    end

    local function settle(result)
        local outcome = result_outcome(result)
        if not outcome then return false end
        local status = loop:status()
        local compaction_id = result.compaction_id
        if compaction_id == nil then compaction_id = false end
        local settled, settlement_error = loop:finish_compaction({
            outcome = outcome,
            compaction_id = compaction_id,
            expected_context_generation = status.context_generation,
            expected_last_sequence = status.last_durable_sequence,
            expected_manifest_digest = status.active_view_manifest_ref,
        })
        if not settled then return nil, settlement_error end
        active = false
        last_result = readonly({
            result = result,
            settlement = settled,
        }, "production compaction result")
        return last_result
    end

    function owner:begin(mode)
        if closed then
            return nil, failure("CompactionClosed", "compaction owner is closed")
        end
        if mode ~= "manual" and mode ~= "automatic" then
            return nil, failure("InvalidCompactionMode", "compaction mode is invalid")
        end
        if active then
            return nil, failure(
                mode == "manual" and "ManualCompactionBusy" or "CompactionBusy",
                "one compaction lifecycle is already active"
            )
        end
        local prepared, prepare_error = build_input(mode)
        if not prepared then return nil, prepare_error end
        if prepared.disabled then
            last_result = readonly({
                result = readonly({ decision = "fits", reason = "automatic-disabled" },
                    "disabled automatic compaction"),
                settlement = false,
            }, "production compaction result")
            return last_result
        end
        local admitted, admission_error = loop:begin_compaction({
            mode = mode,
            preflight_id = mode == "automatic"
                and prepared.status.compaction_preflight_id or false,
            expected_context_generation = prepared.observation
                .expected_context_generation,
            expected_last_sequence = prepared.observation.expected_last_sequence,
            expected_manifest_digest = prepared.observation
                .expected_manifest_digest,
        })
        if not admitted then return nil, admission_error end
        active = true
        local result, begin_error = service:begin(prepared.input)
        if not result then
            local status = loop:status()
            local release_outcome = mode == "automatic"
                and "waiting_user" or "unknown"
            local released, release_error = loop:finish_compaction({
                outcome = release_outcome,
                compaction_id = false,
                expected_context_generation = status.context_generation,
                expected_last_sequence = status.last_durable_sequence,
                expected_manifest_digest = status.active_view_manifest_ref,
            })
            if not released then return nil, release_error end
            active = false
            if mode == "automatic" then
                last_result = readonly({
                    result = readonly({
                        outcome = "waiting_user",
                        reason = "automatic-compaction-preflight-failed",
                        error_code = type(begin_error) == "table"
                            and begin_error.code or "CompactionPreflightFailure",
                    }, "automatic compaction preflight failure"),
                    settlement = released,
                }, "production compaction result")
                return last_result
            end
            return nil, begin_error
        end
        local terminal, settlement_error = settle(result)
        if terminal == nil then return nil, settlement_error end
        if terminal ~= false then return terminal end
        return readonly({
            state = "active",
            compaction_id = result.compaction_id,
            request_id = result.request_id,
            mode = mode,
        }, "production compaction admission")
    end

    function owner:poll()
        if not active then
            return readonly({
                events = readonly({}, "empty compaction event batch"),
                progressed = false,
                status = self:status(),
            }, "production compaction poll")
        end
        local output = {}
        local ticked, tick_error = service:tick()
        if not ticked then return nil, tick_error end
        local tick_terminal, settlement_error = settle(ticked)
        if tick_terminal == nil then return nil, settlement_error end
        if tick_terminal ~= false then
            output[1] = readonly({ kind = "terminal", result = tick_terminal },
                "compaction terminal event")
            return readonly({
                events = readonly(output, "compaction event batch"),
                progressed = true,
                status = self:status(),
            }, "production compaction poll")
        end
        local events, poll_error = catalog.compaction.poll(128)
        if type(events) ~= "table" then return nil, poll_error end
        local progressed = false
        for _, event in ipairs(events) do
            local result, result_error
            if event.kind == "response" then
                result, result_error = service:accept_response(event.response)
            elseif event.kind == "cancel-settled" then
                result, result_error = service:settle_cancel({
                    request_id = event.request_id,
                    outcome = event.outcome,
                })
            else
                return nil, failure(
                    "CompactionActivityContract",
                    "compaction Model port returned an unknown event"
                )
            end
            if not result then return nil, result_error end
            progressed = true
            local terminal, settlement_error = settle(result)
            if terminal == nil then return nil, settlement_error end
            if terminal ~= false then
                output[#output + 1] = readonly({
                    kind = "terminal",
                    result = terminal,
                }, "compaction terminal event")
            else
                output[#output + 1] = readonly({
                    kind = "progress",
                    state = result.state,
                    attempt = result.attempt,
                    request_id = result.request_id,
                }, "compaction progress event")
            end
        end
        return readonly({
            events = readonly(output, "compaction event batch"),
            progressed = progressed,
            status = self:status(),
        }, "production compaction poll")
    end

    function owner:cancel(reason)
        if not active then
            return nil, failure(
                "NoCompactionRequest",
                "no compaction request can be cancelled"
            )
        end
        local result, cancel_error = service:cancel(reason)
        if not result then return nil, cancel_error end
        local terminal, settlement_error = settle(result)
        if terminal == nil then return nil, settlement_error end
        if terminal ~= false then return terminal end
        return readonly({
            state = result.state,
            compaction_id = result.compaction_id,
            cancel_pending = result.cancel_pending == true,
        }, "production compaction cancellation")
    end

    function owner:status()
        local compact_status = service and service:status() or false
        return readonly({
            state = active and (compact_status and compact_status.state or "Unknown")
                or "Idle",
            active = active,
            active_compaction_id = compact_status
                and compact_status.active_compaction_id or false,
            active_request_id = compact_status
                and compact_status.active_request_id or false,
            automatic_enabled = automatic_enabled,
            automatic_failure_count = compact_status
                and compact_status.automatic_failure_count or 0,
            automatic_circuit_state = compact_status
                and compact_status.automatic_circuit_state or "closed",
            last_result = last_result,
            generation = service_generation,
            closed = closed,
        }, "production compaction status")
    end

    function owner:close(reason)
        if closed then return false end
        if active then
            local cancelled, cancel_error = self:cancel(
                reason or "compaction-owner-close"
            )
            if not cancelled then return nil, cancel_error end
            if active then return cancelled end
        end
        if service then service:close(reason or "compaction-owner-close") end
        closed = true
        return true
    end

    return readonly(owner, "production compaction owner")
end

local function network_options(layout)
    return {
        curl_executable = layout.curl_executable,
        bundled_ca_path = layout.ca_bundle_path,
        temporary_directory = layout.data_root,
        private_permissions = 384,
        maximum_body_bytes = 1024 * 1024,
        maximum_header_bytes = 262144,
        maximum_config_bytes = 512 * 1024,
        maximum_output_bytes = 32 * 1024 * 1024,
        maximum_io_chunk_bytes = 65536,
        maximum_attempt_id_bytes = 128,
        maximum_connect_timeout_ms = 120000,
        maximum_total_timeout_ms = 3600000,
        component_environment = {},
    }
end

local CONFIG_REPAIR_TEMPLATE = table.concat({
    "; yaca bootstrap repair template",
    "; This file is intentionally not Agent-ready until Model.Primary is configured",
    "; and explicitly enabled. Run yaca --model-repl for hidden Key input, or edit",
    "; this file manually and run yaca --config-repl to validate it.",
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

local function build_context_services(native, filesystem, data_root, platform_kind)
    local safety = require("safety")
    local xml = require("xml")
    local context = require("context")
    local path = require("path")
    local prompt = require("prompt")
    local tools = require("tools")
    local index = require("index")
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
    local path_service, path_error = path.new(native, {
        maximum_path_bytes = 32768,
        maximum_segments = 256,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 32768,
    })
    if not path_service then return nil, path_error end
    local prompt_service, prompt_error = prompt.new({
        digest = safety_service.digest,
    }, {
        maximum_component_bytes = 32768,
        maximum_quoted_bytes = 16384,
        maximum_total_bytes = 262144,
        maximum_estimated_tokens = 262144,
        maximum_components = 16,
        maximum_source_bytes = 256,
        maximum_version_bytes = 256,
    })
    if not prompt_service then return nil, prompt_error end
    local registry, registry_error = tools.registry_snapshot(safety_service)
    if not registry then return nil, registry_error end
    local context_root = join_path(data_root, "CONTEXT", platform_kind)
    local scanner, verifier, scanner_error = index.new_filesystem_scanner({
        filesystem = filesystem,
        store = store,
        path = path_service,
    }, {
        context_root = context_root,
        platform_kind = platform_kind == "windows" and "windows" or "posix",
        maximum_walk_depth = CONTEXT_SCANNER_OPTIONS.maximum_walk_depth,
        maximum_walk_entries = CONTEXT_SCANNER_OPTIONS.maximum_walk_entries,
    })
    if not scanner then return nil, scanner_error end
    local catalog, catalog_error = index.new({
        path = path_service,
        scanner = scanner,
        verifier = verifier,
    }, CONTEXT_INDEX_OPTIONS)
    if not catalog then return nil, catalog_error end
    return readonly({
        safety = safety_service,
        xml = codec,
        schema = schema,
        store = store,
        path = path_service,
        prompt = prompt_service,
        tool_registry = registry,
        context_root = context_root,
        catalog_scanner = scanner,
        catalog_verifier = verifier,
        catalog = catalog,
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

local function catalog_call(port, method, ...)
    local called, ok, value = pcall(port[method], ...)
    if not called then
        return false, failure(
            "ContextCatalogFailure",
            "Context catalog method raised an exception",
            method
        )
    end
    if ok ~= true then
        return false, type(value) == "table" and value or failure(
            "ContextCatalogFailure",
            "Context catalog method returned an invalid result",
            method
        )
    end
    return true, value
end

local function observe_context_catalog(context_services)
    if type(context_services) ~= "table"
        or type(context_services.catalog_scanner) ~= "table"
        or type(context_services.catalog) ~= "table"
    then
        return nil, failure(
            "ContextCatalogUnavailable",
            "Context catalog services are unavailable"
        )
    end
    local scanner = context_services.catalog_scanner
    local began, handle_or_error = catalog_call(scanner, "begin", "/", {
        maximum_scan_candidates = CONTEXT_INDEX_OPTIONS.maximum_scan_candidates,
        maximum_search_rings = CONTEXT_INDEX_OPTIONS.maximum_search_rings,
    })
    if not began then return nil, handle_or_error end
    local handle = handle_or_error
    local rows = {}
    local complete = true
    local partial_reason = false
    while true do
        local next_ok, ring_or_error = catalog_call(scanner, "next_ring", handle)
        if not next_ok then
            complete = false
            partial_reason = ring_or_error.code or "scanner-next"
            break
        end
        local ring = ring_or_error
        if ring == nil then break end
        if ring.complete ~= true then
            complete = false
            partial_reason = ring.reason or "scan-incomplete"
            break
        end
        for _, candidate in ipairs(ring.candidates) do
            local hash, hash_error = context_services.catalog.current_hash(
                candidate.logical_path
            )
            if not hash then
                complete = false
                partial_reason = type(hash_error) == "table" and hash_error.code
                    or "context-hash"
                break
            end
            rows[#rows + 1] = {
                logical_path = candidate.logical_path,
                display_path = candidate.display_path,
                display_name = candidate.display_name,
                canonical_name = candidate.canonical_name or false,
                created_at = candidate.created_at or false,
                updated_at = candidate.updated_at or false,
                header_state = candidate.header_state,
                hash16 = hash,
            }
        end
        if not complete then break end
    end
    local close_ok, close_error = catalog_call(scanner, "close", handle)
    if not close_ok then
        complete = false
        partial_reason = close_error.code or "scanner-close"
    end
    local called, statistics, status_error = pcall(scanner.status, handle)
    if not called or not statistics then
        return nil, type(status_error) == "table" and status_error or failure(
            "ContextCatalogFailure",
            "Context catalog statistics are unavailable"
        )
    end
    if statistics.complete ~= true then
        complete = false
        if partial_reason == false then
            partial_reason = statistics.partial_reason or "scan-incomplete"
        end
    end
    return {
        complete = complete,
        partial_reason = partial_reason,
        rows = rows,
        statistics = statistics,
        hash_count = #rows,
    }
end

local CATALOG_STATE_ORDER = {
    valid = 1,
    corrupt = 2,
    unavailable = 3,
    changed = 4,
}

local function catalog_row_order(path_service, sort_by, direction)
    return function(left, right)
        local left_state = CATALOG_STATE_ORDER[left.header_state] or 9
        local right_state = CATALOG_STATE_ORDER[right.header_state] or 9
        if left_state ~= right_state then return left_state < right_state end
        if left.header_state == "valid" then
            local left_key = sort_by == "created" and left.created_at
                or sort_by == "name" and left.canonical_name or left.updated_at
            local right_key = sort_by == "created" and right.created_at
                or sort_by == "name" and right.canonical_name or right.updated_at
            if left_key ~= right_key then
                if direction == "ascending" then return left_key < right_key end
                return left_key > right_key
            end
        end
        local order = path_service.compare_logical(
            left.logical_path,
            right.logical_path
        )
        return order < 0
    end
end

local function context_catalog_page(context_services, observation, generation, view)
    local sort_by = "updated"
    local direction = "descending"
    local recent_limit = CONTEXT_RECENT_DEFAULT_LIMIT
    if type(generation) == "table" and type(generation.context) == "table" then
        sort_by = generation.context.list_sort_by or sort_by
        direction = generation.context.list_sort_direction or direction
        recent_limit = generation.context.recent_list_limit or recent_limit
    end
    recent_limit = math.min(recent_limit, CONTEXT_BROWSER_PAGE_LIMIT)
    local ordered = {}
    for index, row in ipairs(observation.rows) do ordered[index] = row end
    table.sort(ordered, catalog_row_order(
        context_services.path,
        sort_by,
        direction
    ))
    local page_limit = view == "recent" and recent_limit or CONTEXT_BROWSER_PAGE_LIMIT
    local rows = {}
    for index = 1, math.min(#ordered, page_limit) do rows[index] = ordered[index] end
    return {
        rows = rows,
        total = #ordered,
        shown = #rows,
        truncated = #rows < #ordered,
        sort_by = sort_by,
        sort_direction = direction,
        page_limit = page_limit,
    }
end

local function build_offline_self_test(runtime)
    local filesystem = runtime.backend.filesystem
    local layout = runtime.layout
    local context_services = runtime.context_services
    local context_error = runtime.context_error
    local native = runtime.native
    local facts = runtime.stdio_facts
    local workspace = workspace_port(native)
    local catalog_snapshot_id
    local catalog_observation
    local catalog_observation_error

    local function stat_file(path)
        local stated, value = filesystem.stat_identity(path)
        return stated and value.kind == "file", value
    end

    local function scan_catalog(specification)
        catalog_snapshot_id = specification.snapshot_id
        catalog_observation, catalog_observation_error = observe_context_catalog(
            context_services
        )
        if not catalog_observation then return nil, catalog_observation_error end
        local roots = {}
        local invalid_roots = 0
        for _, row in ipairs(catalog_observation.rows) do
            local parent = context_services.path.parent(row.logical_path)
            if not parent then
                invalid_roots = invalid_roots + 1
            elseif not roots[parent] then
                roots[parent] = true
                local platform_path = context_services.path.from_logical(
                    parent,
                    runtime.identity.os == "windows" and "windows" or "posix"
                )
                local called, observed = false, nil
                if platform_path then
                    called, observed = pcall(workspace.inspect, platform_path)
                end
                local observed_logical
                if called and observed then
                    observed_logical = context_services.path.to_logical(observed.path)
                end
                local platform_kind = runtime.identity.os == "windows"
                    and "windows" or "posix"
                local expected_key = observed_logical
                    and context_services.path.comparison_key(parent, platform_kind)
                local observed_key = observed_logical
                    and context_services.path.comparison_key(
                        observed_logical,
                        platform_kind
                    )
                if not called or not observed or not expected_key
                    or expected_key ~= observed_key
                then
                    invalid_roots = invalid_roots + 1
                end
            end
        end
        local root_count = 0
        for _ in pairs(roots) do root_count = root_count + 1 end
        catalog_observation.workspace_roots = root_count
        catalog_observation.invalid_roots = invalid_roots
        return catalog_observation
    end

    local function current_catalog(specification)
        if catalog_snapshot_id ~= specification.snapshot_id then
            return scan_catalog(specification)
        end
        return catalog_observation, catalog_observation_error
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
            local observed, observe_error = scan_catalog(specification)
            if not observed then
                return check_result("failed", "Context catalog scan could not start", {
                    "reason=" .. safe_diagnostic(observe_error and observe_error.code, 96),
                })
            end
            local statistics = observed.statistics
            local evidence = {
                "catalog-count=" .. tostring(#observed.rows),
                string.format(
                    "states=valid:%d,corrupt:%d,unavailable:%d,changed:%d",
                    statistics.valid,
                    statistics.corrupt,
                    statistics.unavailable,
                    statistics.changed
                ),
                "busy=" .. tostring(statistics.busy),
                "workspace-roots=" .. tostring(observed.workspace_roots),
                "invalid-roots=" .. tostring(observed.invalid_roots),
                "hashes=" .. tostring(observed.hash_count),
                "scan-cap=" .. tostring(CONTEXT_INDEX_OPTIONS.maximum_scan_candidates),
                "header-bytes=" .. tostring(statistics.header_bytes),
            }
            if not observed.complete then
                return check_result("unknown", "Context catalog scan is incomplete", evidence)
            end
            if statistics.corrupt > 0 then
                return check_result("failed", "Context catalog contains corrupt Headers", evidence)
            end
            if statistics.changed > 0
                or statistics.unavailable > statistics.busy
                or observed.invalid_roots > 0
            then
                return check_result(
                    "unknown",
                    "Context catalog contains unavailable or stale bindings",
                    evidence
                )
            end
            return check_result("passed", "Context catalog is complete and bounded", evidence)
        end
        if id == "ST1-CONTEXT-LOCK" then
            local observed, observe_error = current_catalog(specification)
            if not observed then
                return check_result("failed", "Context lock probe could not scan", {
                    "reason=" .. safe_diagnostic(observe_error and observe_error.code, 96),
                })
            end
            local statistics = observed.statistics
            local evidence = {
                "busy=" .. tostring(statistics.busy),
                "invalid-locks=" .. tostring(statistics.lock_invalid),
                "unavailable-locks=" .. tostring(statistics.lock_unavailable),
            }
            if not observed.complete then
                return check_result("unknown", "Context lock scan is incomplete", evidence)
            end
            if statistics.lock_invalid > 0 then
                return check_result("failed", "Context writer metadata is invalid", evidence)
            end
            if statistics.lock_unavailable > 0 then
                return check_result("unknown", "Context writer metadata is unavailable", evidence)
            end
            return check_result("passed", "Context writer locks were inspected safely", evidence)
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

local function management_service(filesystem, layout, context_services)
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
        if context.action == "context-repl" then
            local observation, observation_error = observe_context_catalog(
                context_services
            )
            if not observation then
                return {
                    outcome = "error",
                    action = context.action,
                    state = "scan-failed",
                    error_code = observation_error.code,
                    view = context.request.view,
                }
            end
            local page = context_catalog_page(
                context_services,
                observation,
                context.config_generation,
                context.request.view
            )
            return {
                outcome = observation.complete and "success" or "action-required",
                action = context.action,
                state = observation.complete and "catalog-ready" or "scan-incomplete",
                error_code = observation.complete and false or "ScanIncomplete",
                partial_reason = observation.partial_reason,
                view = context.request.view,
                rows = page.rows,
                total = page.total,
                shown = page.shown,
                truncated = page.truncated,
                sort_by = page.sort_by,
                sort_direction = page.sort_direction,
                page_limit = page.page_limit,
                statistics = observation.statistics,
                target_qualified = false,
            }
        end
        return {
            outcome = "error",
            action = context.action,
            state = "unsupported-action",
            error_code = "ManagementActionUnavailable",
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
        backend.filesystem,
        layout.data_root,
        runtime.identity.os == "windows" and "windows" or "posix"
    )
    local model_module = require("model")
    local model_adapter, model_error = model_module.new(MODEL_ADAPTER_OPTIONS)
    if not model_adapter then return nil, model_error end
    local network_module = require("network")
    local network_service, network_error = network_module.new({
        filesystem = backend.filesystem,
        processes = backend.processes,
    }, network_options(layout))
    if not network_service then return nil, network_error end
    local publication
    if contexts then
        publication, contexts_error = session.new_context_publication({
            filesystem = backend.filesystem,
            schema = contexts.schema,
            store = contexts.store,
            path = contexts.path,
            safety = contexts.safety,
            prompt = contexts.prompt,
            system = backend.system,
            tool_registry = contexts.tool_registry,
        }, {
            data_root = layout.data_root,
            platform_kind = runtime.identity.os == "windows" and "windows" or "posix",
            maximum_create_attempts = 16,
            maximum_model_view_bytes = 262144,
            maximum_compaction_source_bytes = 16 * 1024 * 1024,
            maximum_compaction_identifier_bytes = 256,
            default_model_request_limit = AGENT_RELEASE_OPTIONS.runtime.hard_caps.model_requests,
            default_tool_call_limit = AGENT_RELEASE_OPTIONS.runtime.hard_caps.tool_calls,
            maximum_queue_items = AGENT_RELEASE_OPTIONS.runtime.lanes.queue_maximum,
        })
        if not publication then contexts = nil end
    end
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
        model_adapter = model_adapter,
        network = network_service,
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
    local application_components = {
        platform = { identity = function() return runtime.identity end },
        config = config_service,
        workspace = workspace_port(runtime.native),
        self_test = self_test,
        management = management_service(backend.filesystem, layout, contexts),
    }
    if publication then application_components.publication = publication end
    if contexts and publication then
        application_components.context_catalog = {
            resolver = contexts.catalog,
            path = contexts.path,
        }
    end
    local application, application_error = M.new(application_components, {
        product_name = "yaca",
        product_version = "0.1.0",
        release_target = runtime.identity.target,
        config_path = layout.config_path,
        maximum_draft_bytes = 16384,
    })
    if not application then return nil, application_error end
    return readonly({
        application = application,
        native = runtime.native,
        identity = runtime.identity,
        layout = layout,
        backend = backend,
        config = config_service,
        contexts = contexts or false,
        context_error = contexts_error or false,
        publication = publication or false,
        model_adapter = model_adapter,
        network = network_service,
        model_activity_options = assert(freeze(
            MODEL_ACTIVITY_OPTIONS,
            {},
            "production model activity options"
        )),
    }, "production runtime composition")
end

---Composes the production Agent over either a newly published first turn or a
-- verified, quiescent existing Context. No Model request or Tool effect is
-- reachable before the relevant durable writer and Runtime bindings succeed.
-- Every later main turn reloads the complete Config and atomically replaces
-- its generation-bound Model/Tool/review ports while all are idle.
function M.start_published_agent(composed, chat, message, source)
    local continuing = type(chat) == "table" and chat.kind == "continue-chat"
    if type(composed) ~= "table"
        or type(composed.backend) ~= "table"
        or type(composed.contexts) ~= "table"
        or type(composed.publication) ~= "table"
        or type(composed.model_adapter) ~= "table"
        or type(composed.network) ~= "table"
        or type(composed.identity) ~= "table"
        or type(composed.config) ~= "table"
        or type(composed.config.reload_file) ~= "function"
        or type(composed.layout) ~= "table"
        or type(composed.layout.config_path) ~= "string"
        or type(composed.publication.turn_context) ~= "function"
        or type(composed.publication.capture_turn) ~= "function"
        or type(composed.publication.update_session) ~= "function"
        or type(chat) ~= "table"
        or (chat.kind ~= "run-chat" and chat.kind ~= "continue-chat")
        or chat.outcome ~= "ready"
        or type(chat.draft) ~= "table"
        or type(chat.draft.status) ~= "function"
        or type(chat.draft.config_generation) ~= "function"
        or type(chat.draft.close) ~= "function"
        or (continuing and type(chat.draft.open_receipt) ~= "function")
        or (not continuing and (
            type(chat.draft.begin_main) ~= "function"
            or type(chat.draft.agent_handoff) ~= "function"
        ))
        or type(message) ~= "string"
        or message == ""
    then
        return nil, failure(
            "InvalidAgentComposition",
            "a ready production chat and nonempty first message are required"
        )
    end
    source = source or "terminal"
    local receipt
    local initial_snapshot
    local handoff
    local generation = chat.draft.config_generation()
    local status = chat.draft.status()
    if continuing then
        receipt = chat.draft.open_receipt()
        if type(receipt) ~= "table"
            or receipt.durable ~= true
            or receipt.auto_continue ~= true
            or not valid_integer(receipt.generation, 1)
            or not valid_integer(receipt.event_count, 0)
            or receipt.last_sequence ~= receipt.event_count
            or type(receipt.runtime_initial_serials) ~= "table"
            or type(receipt.view_manifest_snapshot) ~= "string"
            or receipt.view_manifest_snapshot == ""
        then
            chat.draft.close()
            return nil, failure(
                "InvalidAgentComposition",
                "the existing Context receipt is not safe to continue"
            )
        end
        local snapshot_error
        initial_snapshot, snapshot_error = composed.publication.capture_turn({
            generation = generation,
            kind = "main",
            text = message,
            source = source,
            expected_context_generation = receipt.generation,
        })
        if not initial_snapshot then
            chat.draft.close()
            return nil, snapshot_error
        end
    else
        local publication_error
        receipt, publication_error = chat.draft.begin_main(message, source)
        if not receipt then return nil, publication_error end
        local handoff_error
        handoff, handoff_error = chat.draft.agent_handoff()
        if not handoff then
            chat.draft.close()
            return nil, handoff_error
        end
        initial_snapshot = handoff.input
    end

    local contexts = composed.contexts
    local operation_journal = composed.publication.operation_journal()
    local context_module = require("context")
    local operations, operation_error = context_module.new_operation_service({
        safety = contexts.safety,
        journal = operation_journal,
    }, assert(copy_plain(AGENT_RELEASE_OPTIONS.operation, {})))
    if not operations then chat.draft.close(); return nil, operation_error end
    local clock = production_clock(composed.backend)
    local json_module = require("json")
    local codec, codec_error = json_module.new(AGENT_RELEASE_OPTIONS.json)
    if not codec then chat.draft.close(); return nil, codec_error end
    local shared = {
        operations = operations,
        operation_journal = operation_journal,
        clock = clock,
        codec = codec,
    }
    local first_ports, first_ports_error = build_turn_ports(composed, shared, {
        generation = generation,
        context_hash = status.context_hash,
        workspace = status.workspace,
        model = status.model,
        permission = status.permission,
        double_check = status.double_check,
        context_prompt = status.context_prompt,
        initial_message = initial_snapshot.text,
        config_snapshot = initial_snapshot.config_generation,
        model_snapshot = initial_snapshot.model_snapshot,
        permission_snapshot = initial_snapshot.permission_snapshot,
        prompt_snapshot = initial_snapshot.prompt_snapshot,
        tool_registry_snapshot = initial_snapshot.tool_registry_snapshot,
    })
    if not first_ports then chat.draft.close(); return nil, first_ports_error end
    local catalog = new_turn_catalog(first_ports)
    local side_catalog = new_side_catalog()
    local durable_settings_generation = generation

    local function reload_turn_snapshot(specification)
        local turn_context, context_error = composed.publication.turn_context({
            expected_context_generation = specification.context_generation,
        })
        if not turn_context then return nil, nil, context_error end
        local next_generation, generation_error = composed.config.reload_file(
            composed.layout.config_path,
            turn_context.overrides
        )
        if not next_generation then return nil, nil, generation_error end
        local snapshot, snapshot_error = composed.publication.capture_turn({
            generation = next_generation,
            kind = specification.kind,
            text = specification.text,
            source = specification.source,
            expected_context_generation = specification.context_generation,
        })
        if not snapshot then return nil, nil, snapshot_error end
        return next_generation, snapshot
    end

    local snapshots = readonly({
        capture = function(specification)
            if type(specification) ~= "table"
                or (specification.kind ~= "main" and specification.kind ~= "side")
            then
                return nil, failure(
                    "InvalidTurnSnapshot",
                    "production snapshot catalog accepts only main or side turns"
                )
            end
            if specification.kind == "main" and not catalog.idle() then
                return nil, failure(
                    "TurnActivitiesBusy",
                    "a later turn cannot replace active generation ports"
                )
            end
            if specification.kind == "side" and not side_catalog.idle() then
                return nil, failure(
                    "SideActivityBusy",
                    "a side turn cannot replace an active side generation"
                )
            end
            local next_generation, snapshot, snapshot_error = reload_turn_snapshot(
                specification
            )
            if not next_generation then return nil, snapshot_error end
            if specification.kind == "main" then
                local candidate, candidate_error = build_turn_ports(composed, shared, {
                    generation = next_generation,
                    context_hash = status.context_hash,
                    workspace = status.workspace,
                    model = next_generation.current_model,
                    permission = next_generation.current_permission,
                    double_check = next_generation.effective_double_check,
                    context_prompt = next_generation.context_prompt or "",
                    initial_message = snapshot.text,
                    config_snapshot = snapshot.config_generation,
                    model_snapshot = snapshot.model_snapshot,
                    permission_snapshot = snapshot.permission_snapshot,
                    prompt_snapshot = snapshot.prompt_snapshot,
                    tool_registry_snapshot = snapshot.tool_registry_snapshot,
                })
                if not candidate then return nil, candidate_error end
                local replaced, replace_error = catalog.replace(candidate)
                if not replaced then return nil, replace_error end
                durable_settings_generation = next_generation
            else
                local candidate, candidate_error = build_side_activity(composed, {
                    generation = next_generation,
                    context_hash = status.context_hash,
                    model = next_generation.current_model,
                    permission = next_generation.current_permission,
                    context_prompt = next_generation.context_prompt or "",
                    initial_message = snapshot.text,
                    model_snapshot = snapshot.model_snapshot,
                    permission_snapshot = snapshot.permission_snapshot,
                    prompt_snapshot = snapshot.prompt_snapshot,
                    tool_registry_snapshot = snapshot.tool_registry_snapshot,
                    view_manifest_ref = snapshot.view_manifest_ref,
                })
                if not candidate then return nil, candidate_error end
                local prepared, prepare_error = side_catalog.prepare(candidate)
                if not prepared then return nil, prepare_error end
            end
            return snapshot
        end,
    }, "production turn snapshot port")

    local runtime_module = require("runtime")
    local loop_options = runtime_options()
    if not loop_options then
        chat.draft.close()
        return nil, failure("InvalidAgentOptions", "production Agent caps could not be copied")
    end
    if continuing then
        local restored_serials, restored_ok = copy_plain(
            receipt.runtime_initial_serials,
            {}
        )
        if not restored_ok then
            chat.draft.close()
            return nil, failure(
                "InvalidAgentOptions",
                "existing Context Runtime serials could not be restored"
            )
        end
        loop_options.initial_sequence = receipt.event_count
        loop_options.initial_context_generation = receipt.generation
        loop_options.initial_view_manifest_ref = receipt.view_manifest_snapshot
        loop_options.initial_serials = restored_serials
    end
    local loop, loop_error = runtime_module.new_agent_loop({
        clock = clock,
        journal = composed.publication,
        model = catalog.model,
        tools = catalog.tools,
        reviews = catalog.reviews,
        snapshots = snapshots,
        side = side_catalog,
        views = readonly({
            prepare = composed.publication.prepare_view,
        }, "active durable Model view publication"),
    }, loop_options)
    if not loop then chat.draft.close(); return nil, loop_error end
    local function fail_after_loop(agent_error)
        -- resume_published_main may already own an active network/tool handle.
        -- Closing is best-effort here: the original construction failure stays
        -- authoritative, while AgentLoop still gets its typed cancellation path.
        pcall(loop.close, loop, "agent-composition-failed")
        chat.draft.close()
        return nil, agent_error
    end
    if type(loop.adopt_session_override) ~= "function"
        or type(loop.fail_session_override_barrier) ~= "function"
    then
        return fail_after_loop(failure(
            "InvalidAgentComposition",
            "Runtime Session receipt ports are incomplete"
        ))
    end
    local session_settings = {}

    local function settings_projection(
        active_generation,
        overrides,
        context_generation,
        effective_at
    )
        return readonly({
            context_generation = context_generation,
            config_generation = active_generation.id,
            model = active_generation.current_model,
            permission = active_generation.current_permission,
            double_check_default = active_generation.agent.double_check,
            double_check_override = overrides.DoubleCheckOverride,
            double_check_effective = active_generation.effective_double_check,
            context_prompt = active_generation.context_prompt or "",
            effective_at = effective_at,
        }, "durable Session settings")
    end

    local function session_update_observation()
        local runtime_status = loop:status()
        if runtime_status.halted == true then
            return nil, failure(
                "SessionUpdateUnavailable",
                "the halted Runtime cannot change Session settings"
            )
        end
        if runtime_status.state == "Closing"
            or runtime_status.compaction_state ~= "idle"
            or runtime_status.compaction_preflight_state ~= "idle"
        then
            return nil, failure(
                "SessionUpdateBusy",
                "Session settings cannot change during close or compaction"
            )
        end
        local turn_context, context_error = composed.publication.turn_context({
            expected_context_generation = runtime_status.context_generation,
        })
        if not turn_context then return nil, context_error end
        return runtime_status, turn_context
    end

    function session_settings:status()
        local runtime_status, turn_context = session_update_observation()
        if not runtime_status then return nil, turn_context end
        return settings_projection(
            durable_settings_generation,
            turn_context.overrides,
            runtime_status.context_generation,
            "current"
        )
    end

    function session_settings:update(change)
        if type(change) ~= "table" then
            return nil, failure(
                "InvalidSessionUpdate",
                "a typed Session setting change is required"
            )
        end
        local allowed = { name = true, value = true, mode = true }
        for key in pairs(change) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "Session setting change contains an unknown field"
                )
            end
        end
        local runtime_status, turn_context = session_update_observation()
        if not runtime_status then return nil, turn_context end
        local next_overrides = {}
        for key, value in pairs(turn_context.overrides) do
            next_overrides[key] = value
        end
        if change.name == "CurrentModel"
            or change.name == "CurrentPermission"
            or change.name == "DoubleCheckOverride"
            or change.name == "ContextPrompt"
        then
            if change.mode ~= nil then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "this Session setting does not accept a mode"
                )
            end
            next_overrides[change.name] = change.value
        elseif change.name == "DoubleCheckGoalOverride" then
            if change.mode == "inherit" then
                next_overrides.DoubleCheckGoalOverride = "inherit"
            elseif change.mode == "value" then
                next_overrides.DoubleCheckGoalOverride = change.value
            else
                return nil, failure(
                    "InvalidSessionUpdate",
                    "DoubleCheck goal change requires inherit or value mode"
                )
            end
        else
            return nil, failure(
                "InvalidSessionUpdate",
                "Session setting name is unavailable"
            )
        end
        local next_generation, generation_error = composed.config.reload_file(
            composed.layout.config_path,
            next_overrides
        )
        if not next_generation then return nil, generation_error end
        local publish_called, record, receipt = pcall(
            composed.publication.update_session,
            {
                expected_context_generation = runtime_status.context_generation,
                expected_last_sequence = runtime_status.last_durable_sequence,
                expected_manifest_digest = runtime_status.active_view_manifest_ref,
                generation = next_generation,
                name = change.name,
                value = change.value,
                mode = change.mode,
            }
        )
        if not publish_called then
            local _, barrier_error = loop:fail_session_override_barrier(
                "publication-exception"
            )
            return nil, barrier_error or failure(
                "SessionUpdateFailure",
                "Session publication raised an exception"
            )
        end
        if not record then
            if type(receipt) == "table"
                and receipt.code == "ContextPublicationUnknown"
            then
                local _, barrier_error = loop:fail_session_override_barrier(
                    "publication-unknown"
                )
                return nil, barrier_error or receipt
            end
            return nil, receipt
        end
        local adoption_called, adopted, adoption_error = pcall(
            loop.adopt_session_override,
            loop,
            record,
            receipt
        )
        if not adoption_called then
            local _, barrier_error = loop:fail_session_override_barrier(
                "adoption-exception"
            )
            return nil, barrier_error or failure(
                "SessionUpdateFailure",
                "Session receipt adoption raised an exception"
            )
        end
        if not adopted then return nil, adoption_error end
        durable_settings_generation = next_generation
        return settings_projection(
            next_generation,
            next_overrides,
            adopted.context_generation,
            adopted.effective_at
        )
    end

    session_settings = readonly(
        session_settings,
        "production Session settings owner"
    )
    local compaction_owner, compaction_error = new_production_compaction(
        composed,
        catalog,
        loop,
        clock
    )
    if not compaction_owner then return fail_after_loop(compaction_error) end
    local admission = false
    if not continuing then
        local admission_error
        admission, admission_error = loop:resume_published_main(handoff)
        if not admission then return fail_after_loop(admission_error) end
    end
    local driver, driver_error = runtime_module.new_agent_activity_driver({
        loop = loop,
        model = catalog.model,
        tools = catalog.tools,
        reviews = catalog.reviews,
        side = side_catalog,
        clock = clock,
    }, AGENT_RELEASE_OPTIONS.driver)
    if not driver then return fail_after_loop(driver_error) end
    local agent_session, session_error = session.new_agent_session(loop, {
        maximum_draft_bytes = 16384,
    })
    if not agent_session then return fail_after_loop(session_error) end

    return readonly({
        admission = admission,
        loop = loop,
        driver = driver,
        session = agent_session,
        tools = catalog.tools,
        settings = session_settings,
        compaction = compaction_owner,
        draft = chat.draft,
        generation = generation,
        current_generation = catalog.generation,
        current_side_generation = side_catalog.generation,
        capabilities = readonly({
            published_first_turn = not continuing,
            reopened_existing_context = continuing,
            model = true,
            tools = true,
            reviews = true,
            approvals = true,
            later_turn_snapshots = true,
            side = true,
            session_settings = true,
            compaction = true,
            target_qualified = false,
        }, "published Agent capabilities"),
    }, "published production Agent")
end

local COORDINATOR_OPTION_FIELDS = {
    close_poll_steps = true,
    idle_wait_ms = true,
    maximum_assistant_bytes = true,
    maximum_draft_bytes = true,
    terminal_poll_events = true,
}

local function coordinator_options(options)
    if type(options) ~= "table" then
        return nil, failure(
            "InvalidCoordinatorOptions",
            "ApplicationCoordinator hard limits are required"
        )
    end
    for key in pairs(options) do
        if type(key) ~= "string" or not COORDINATOR_OPTION_FIELDS[key] then
            return nil, failure(
                "InvalidCoordinatorOptions",
                "ApplicationCoordinator options contain an unknown field"
            )
        end
    end
    if not valid_integer(options.close_poll_steps, 1)
        or not valid_integer(options.idle_wait_ms, 0)
        or options.idle_wait_ms > 60000
        or not valid_integer(options.maximum_assistant_bytes, 1)
        or not valid_integer(options.maximum_draft_bytes, 1)
        or not valid_integer(options.terminal_poll_events, 1)
        or options.terminal_poll_events > options.maximum_draft_bytes
    then
        return nil, failure(
            "InvalidCoordinatorOptions",
            "ApplicationCoordinator limits are invalid"
        )
    end
    return {
        close_poll_steps = options.close_poll_steps,
        idle_wait_ms = options.idle_wait_ms,
        maximum_assistant_bytes = options.maximum_assistant_bytes,
        maximum_draft_bytes = options.maximum_draft_bytes,
        terminal_poll_events = options.terminal_poll_events,
    }
end

local function coordinator_ports(ports)
    if type(ports) ~= "table"
        or type(ports.terminal) ~= "table"
        or type(ports.clock) ~= "table"
        or type(ports.cli) ~= "table"
        or type(ports.view) ~= "table"
        or type(ports.chat) ~= "table"
        or type(ports.chat.draft) ~= "table"
        or type(ports.context_switch) ~= "table"
        or type(ports.agent_factory) ~= "function"
        or type(ports.idle_wait) ~= "function"
        or type(ports.clock.now) ~= "function"
        or type(ports.cli.parse_chat) ~= "function"
        or type(ports.cli.render_help) ~= "function"
        or type(ports.view.startup) ~= "function"
        or type(ports.view.publish) ~= "function"
        or type(ports.view.prompt) ~= "function"
        or (ports.initial_agent ~= nil and (
            type(ports.initial_agent) ~= "table"
            or type(ports.initial_agent.loop) ~= "table"
            or type(ports.initial_agent.driver) ~= "table"
            or type(ports.initial_agent.session) ~= "table"
            or type(ports.initial_agent.settings) ~= "table"
            or type(ports.initial_agent.settings.status) ~= "function"
            or type(ports.initial_agent.settings.update) ~= "function"
            or type(ports.initial_agent.tools) ~= "table"
            or type(ports.initial_agent.compaction) ~= "table"
            or type(ports.initial_agent.draft) ~= "table"
        ))
    then
        return nil, failure(
            "InvalidCoordinatorPorts",
            "ApplicationCoordinator ports are incomplete"
        )
    end
    for _, method in ipairs({
        "start", "poll", "cancel", "join", "restore", "close",
    }) do
        if type(ports.terminal[method]) ~= "function" then
            return nil, failure(
                "InvalidCoordinatorPorts",
                "terminal port omits " .. method
            )
        end
    end
    for _, method in ipairs({ "list", "preview", "activate" }) do
        if type(ports.context_switch[method]) ~= "function" then
            return nil, failure(
                "InvalidCoordinatorPorts",
                "Context switch port omits " .. method
            )
        end
    end
    if type(ports.facts) ~= "table" then
        return nil, failure(
            "InvalidCoordinatorPorts",
            "interactive file descriptor facts are required"
        )
    end
    return ports
end

local function coordinator_call(owner, method, code, message, ...)
    local called, result, result_error = pcall(owner[method], owner, ...)
    if not called then return nil, failure(code, message .. " raised an exception") end
    if result == nil then return nil, result_error or failure(code, message .. " failed") end
    return result, result_error
end

local function coordinator_function(callable, code, message, ...)
    local called, result, result_error = pcall(callable, ...)
    if not called then return nil, failure(code, message .. " raised an exception") end
    if result == nil then return nil, result_error or failure(code, message .. " failed") end
    return result, result_error
end

local function coordinator_error_id(value)
    local code = type(value) == "table" and value.code or "InternalError"
    if type(code) ~= "string" or not code:match("^[A-Za-z][A-Za-z0-9]+$") then
        return "InternalError"
    end
    return code
end

local function trim_coordinator_line(value)
    return value:match("^%s*(.-)%s*$")
end

---Creates the single-threaded application owner for one interactive chat.
-- Terminal observations, typed Agent actions, approvals, and renderer blocks
-- all pass through this owner.  It uses bounded polling and an injected idle
-- wait, never infers domain state from already-rendered output, and restores
-- the terminal on every returned path.
-- @param ports table Terminal, clock, CLI, view, chat, and Agent factory ports.
-- @param options table Fixed input, output, polling, wait, and close limits.
-- @return table|nil coordinator Readonly coordinator with a run method.
-- @return table|nil err Structured construction failure.
function M.new_application_coordinator(ports, options)
    local admitted_ports, ports_error = coordinator_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local admitted, options_error = coordinator_options(options)
    if not admitted then return nil, options_error end

    local lifecycle = "created"
    local terminal_started = false
    local terminal_ended = false
    local terminal_outcome = false
    local agent = admitted_ports.initial_agent or false
    local input_draft = ""
    local assistant_draft = ""
    local side_draft = ""
    local side_draft_id = false
    local side_focus_id = false
    local last_now
    local prompt_needed = false
    local approval = false
    local approval_serial = 0
    local tool_serial = 0
    local steer_serial = 0
    local tool_ids = {}
    local last_wait_key = false
    local deferred_failure = false
    local close_agent
    local diagnostic_serial = 0
    local diagnostic_order = {}
    local diagnostics_by_id = {}
    local coordinator = {}

    local function now()
        local observed, clock_error = coordinator_function(
            admitted_ports.clock.now,
            "MonotonicClockFailure",
            "ApplicationCoordinator clock"
        )
        if not valid_integer(observed, 0)
            or (last_now ~= nil and observed < last_now)
        then
            return nil, clock_error or failure(
                "MonotonicClockFailure",
                "ApplicationCoordinator clock is invalid"
            )
        end
        last_now = observed
        return observed
    end

    local function publish(block)
        local published, publish_error = coordinator_call(
            admitted_ports.view,
            "publish",
            "RendererFailure",
            "semantic transcript publication",
            block
        )
        if not published then return nil, publish_error end
        return true
    end

    local function publish_error(value)
        local message = type(value) == "table" and value.message or nil
        if type(message) ~= "string" or message == "" then
            message = "An internal operation failed."
        end
        local code = coordinator_error_id(value)
        if diagnostic_serial == math.maxinteger then
            return nil, failure(
                "DiagnosticLimit",
                "interactive diagnostic identity space is exhausted"
            )
        end
        diagnostic_serial = diagnostic_serial + 1
        local diagnostic_id = "error-" .. tostring(diagnostic_serial)
        local suggestion = type(value) == "table" and value.suggestion or nil
        if type(suggestion) ~= "string" or suggestion == "" then suggestion = false end
        diagnostics_by_id[diagnostic_id] = {
            id = diagnostic_id,
            code = code,
            message = safe_diagnostic(message, 4096),
            suggestion = suggestion and safe_diagnostic(suggestion, 1024) or false,
        }
        diagnostic_order[#diagnostic_order + 1] = diagnostic_id
        if #diagnostic_order > 64 then
            local expired = table.remove(diagnostic_order, 1)
            diagnostics_by_id[expired] = nil
        end
        return publish({
            kind = "error",
            id = diagnostic_id,
            text = code .. ": " .. safe_diagnostic(message, 4096)
                .. " (details: .details " .. diagnostic_id .. ")",
        })
    end

    local function publish_status(message)
        return publish({ kind = "status", text = message })
    end

    local function show_prompt(focus)
        local shown, prompt_error = coordinator_call(
            admitted_ports.view,
            "prompt",
            "RendererFailure",
            "interactive prompt publication",
            focus
        )
        if not shown then return nil, prompt_error end
        prompt_needed = false
        return true
    end

    local function tool_display_id(canonical_id)
        local display_id = tool_ids[canonical_id]
        if display_id then return display_id end
        tool_serial = tool_serial + 1
        display_id = "tool-" .. tostring(tool_serial)
        tool_ids[canonical_id] = display_id
        return display_id
    end

    local function flush_assistant()
        if assistant_draft == "" then return true end
        local value = assistant_draft
        assistant_draft = ""
        return publish({ kind = "assistant", text = value })
    end

    local function append_assistant(value)
        if type(value) ~= "string"
            or #assistant_draft + #value > admitted.maximum_assistant_bytes
        then
            return nil, failure(
                "CoordinatorOutputLimit",
                "assistant transcript exceeds its fixed byte limit"
            )
        end
        assistant_draft = assistant_draft .. value
        return true
    end

    local function flush_side(side_id)
        if side_draft == "" then
            side_draft_id = false
            return true
        end
        if type(side_id) ~= "string" or side_id == "" or side_id ~= side_draft_id then
            return nil, failure(
                "SideActivityContract",
                "side transcript identity changed while streaming"
            )
        end
        local value = side_draft
        side_draft = ""
        side_draft_id = false
        return publish({ kind = "side", id = side_id, text = value })
    end

    local function append_side(side_id, value)
        if type(side_id) ~= "string" or side_id == ""
            or type(value) ~= "string"
            or (side_draft_id ~= false and side_draft_id ~= side_id)
            or #side_draft + #value > admitted.maximum_assistant_bytes
        then
            return nil, failure(
                "CoordinatorOutputLimit",
                "side transcript exceeds its fixed byte limit or binding"
            )
        end
        side_draft_id = side_id
        side_draft = side_draft .. value
        return true
    end

    local function project_side_model_event(side_id, event)
        if type(event) ~= "table" or type(event.kind) ~= "string" then
            return nil, failure(
                "SideActivityContract",
                "interactive side Model event is invalid"
            )
        end
        if event.kind == "response_start"
            or event.kind == "usage_update"
            or event.kind == "reasoning_summary_delta"
            or event.kind == "tool_arguments_delta"
        then
            return true
        end
        if event.kind == "text_delta" then return append_side(side_id, event.text) end
        if event.kind == "response_finish" then return flush_side(side_id) end
        if event.kind == "tool_call_start"
            or event.kind == "tool_call_complete"
            or event.kind == "control"
        then
            local flushed, flush_error = flush_side(side_id)
            if not flushed then return nil, flush_error end
            return publish_error({
                code = "InvalidSideResponse",
                message = "The side Model attempted a Tool or control action; it was rejected.",
            })
        end
        if event.kind == "protocol_error" or event.kind == "transport_error" then
            local flushed, flush_error = flush_side(side_id)
            if not flushed then return nil, flush_error end
            return publish_error({
                code = "SideModelResponseError",
                message = "Side Model response failed: " .. tostring(event.error_id),
            })
        end
        return nil, failure(
            "SideActivityContract",
            "interactive side Model event kind is unknown"
        )
    end

    local function project_model_event(event)
        if type(event) ~= "table" or type(event.kind) ~= "string" then
            return nil, failure(
                "ModelActivityContract",
                "interactive Model event is invalid"
            )
        end
        if event.kind == "response_start"
            or event.kind == "usage_update"
            or event.kind == "reasoning_summary_delta"
            or event.kind == "tool_arguments_delta"
        then
            return true
        end
        if event.kind == "text_delta" then return append_assistant(event.text) end
        if event.kind == "response_finish" then return flush_assistant() end
        if event.kind == "tool_call_start" or event.kind == "tool_call_complete" then
            local flushed, flush_error = flush_assistant()
            if not flushed then return nil, flush_error end
            local canonical_id = event.local_tool_call_id
            if type(canonical_id) ~= "string" or canonical_id == "" then
                return nil, failure(
                    "ModelActivityContract",
                    "Model Tool event omits its local identity"
                )
            end
            local lines = { "name: " .. tostring(event.name or "unknown") }
            if event.kind == "tool_call_complete" then
                lines[#lines + 1] = "arguments: "
                    .. tostring(event.canonical_arguments or "{}")
            else
                lines[#lines + 1] = "requested"
            end
            return publish({
                kind = "tool",
                id = tool_display_id(canonical_id),
                lines = lines,
            })
        end
        if event.kind == "control" then
            local flushed, flush_error = flush_assistant()
            if not flushed then return nil, flush_error end
            return publish_status("Model control: " .. tostring(event.control))
        end
        if event.kind == "protocol_error" or event.kind == "transport_error" then
            local flushed, flush_error = flush_assistant()
            if not flushed then return nil, flush_error end
            return publish_error({
                code = "ModelResponseError",
                message = "Model response failed: " .. tostring(event.error_id),
            })
        end
        return nil, failure(
            "ModelActivityContract",
            "interactive Model event kind is unknown"
        )
    end

    local function project_tool_event(event, active_tool_call_id)
        if type(event) ~= "table" or type(event.kind) ~= "string" then
            return nil, failure(
                "ToolActivityContract",
                "interactive Tool event is invalid"
            )
        end
        local display_id = tool_display_id(active_tool_call_id or "active-tool")
        if event.kind == "io_progress" then
            return publish({
                kind = "tool",
                id = display_id,
                text = tostring(event.stream or event.key or "output")
                    .. ": " .. tostring(event.content or "progress received"),
            })
        end
        if event.kind == "io_terminal" then
            return publish({
                kind = "tool",
                id = display_id,
                text = "process outcome: " .. tostring(event.outcome),
            })
        end
        return nil, failure(
            "ToolActivityContract",
            "interactive Tool event kind is unknown"
        )
    end

    local function project_transition(event)
        local result = event.result
        if type(result) ~= "table" then
            return nil, failure(
                "AgentDriverFailure",
                "interactive Runtime transition omits its typed result"
            )
        end
        if event.cause == "model-response" then
            local flushed, flush_error = flush_assistant()
            if not flushed then return nil, flush_error end
            if type(result.question) == "string" and result.question ~= "" then
                return publish({ kind = "notice", text = result.question })
            end
            if result.auto_started_queue_item then
                return publish_status(
                    "Started queued input " .. tostring(result.auto_started_queue_item)
                )
            end
            return true
        end
        if event.cause == "tool-result" then
            return publish_status("Tool result was committed before the next Model request.")
        end
        if event.cause == "action-review" then
            return publish_status("Action review completed.")
        end
        if event.cause == "termination-review" then
            return publish_status("Termination review completed.")
        end
        if event.cause == "side-response" then
            local flushed, flush_error = flush_side(event.side_id)
            if not flushed then return nil, flush_error end
            if side_focus_id == event.side_id then side_focus_id = false end
            return publish_status(
                "Side " .. tostring(event.side_id)
                    .. " outcome: " .. tostring(result.outcome)
            )
        end
        return nil, failure(
            "AgentDriverFailure",
            "interactive Runtime transition cause is unknown"
        )
    end

    local function project_driver_events(step, before)
        for _, event in ipairs(step.events) do
            local projected, projection_error
            if event.kind == "model-event" then
                projected, projection_error = project_model_event(event.event)
            elseif event.kind == "side-model-event" then
                projected, projection_error = project_side_model_event(
                    event.side_id,
                    event.event
                )
            elseif event.kind == "tool-event" then
                projected, projection_error = project_tool_event(
                    event.event,
                    before.active_tool_call_id
                )
            elseif event.kind == "runtime-transition" then
                projected, projection_error = project_transition(event)
            else
                projected, projection_error = nil, failure(
                    "AgentDriverFailure",
                    "interactive Agent driver event is unknown"
                )
            end
            if not projected then return nil, projection_error end
        end
        return true
    end

    local function approval_lines(action_id, snapshot)
        local capabilities = snapshot.required_capabilities
        local rendered_capabilities = "none"
        if type(capabilities) == "table" then
            rendered_capabilities = table.concat(capabilities, ",")
        end
        local target = snapshot.canonical_target
        if target == "" then target = "(opaque command)" end
        return {
            "tool: " .. tostring(snapshot.tool),
            "target: " .. tostring(target),
            "cwd: " .. tostring(snapshot.cwd),
            "capabilities: " .. rendered_capabilities,
            "arguments: " .. tostring(snapshot.canonical_arguments),
            "snapshot: " .. tostring(snapshot.snapshot_digest),
            "allow " .. action_id .. " once | deny " .. action_id
                .. " | details " .. action_id,
            "default: deny",
        }
    end

    local function ensure_approval(status)
        if status.state ~= "AwaitingApproval"
            and not (status.state == "WaitingUser"
                and status.pending_kind == "approval")
        then
            approval = false
            return true
        end
        if approval and approval.tool_call_id == status.pending_tool_call_id then
            return true
        end
        if type(status.pending_tool_call_id) ~= "string"
            or status.pending_tool_call_id == ""
        then
            return nil, failure(
                "ApprovalBindingUnavailable",
                "Runtime did not project the exact pending Tool approval"
            )
        end
        local review_verdict = status.pending_review_verdict
        if review_verdict == false then review_verdict = nil end
        local snapshot, snapshot_error = coordinator_function(
            agent.tools.prepare_approval,
            "ApprovalSnapshotFailure",
            "Tool approval snapshot",
            status.pending_tool_call_id,
            review_verdict
        )
        if not snapshot then return nil, snapshot_error end
        approval_serial = approval_serial + 1
        local action_id = "approval-" .. tostring(approval_serial)
        approval = {
            action_id = action_id,
            tool_call_id = status.pending_tool_call_id,
            operation_id = status.pending_operation_id,
            review_verdict = review_verdict,
            snapshot = snapshot,
            lines = approval_lines(action_id, snapshot),
        }
        local published, publish_error = publish({
            kind = "action",
            id = action_id,
            lines = approval.lines,
        })
        if not published then return nil, publish_error end
        prompt_needed = true
        return true
    end

    local function project_wait(status)
        local key = tostring(status.turn_id) .. "\0" .. tostring(status.state)
            .. "\0" .. tostring(status.pending_kind)
            .. "\0" .. tostring(status.last_outcome)
        if key == last_wait_key then return true end
        last_wait_key = key
        if status.state == "WaitingUser" and status.pending_kind == "ask-user" then
            if type(status.pending_question) == "string"
                and status.pending_question ~= ""
            then
                return publish({ kind = "notice", text = status.pending_question })
            end
            return publish_status("The Agent is waiting for a user answer.")
        end
        if status.state == "WaitingUser" and status.pending_kind == "model-yield" then
            return publish_status(
                "The Model yielded without finish; the next message starts a fresh turn."
            )
        end
        if status.state == "Idle" and status.last_outcome ~= false then
            return publish_status("Turn outcome: " .. tostring(status.last_outcome))
        end
        if status.state == "Closing" then return publish_status("Session closed.") end
        return true
    end

    local function drive_agent()
        if not agent then return false end
        local before = agent.loop:status()
        local step, step_error = coordinator_function(
            agent.driver.step,
            "AgentDriverFailure",
            "Agent activity driver"
        )
        if not step then return nil, step_error end
        local projected, projection_error = project_driver_events(step, before)
        if not projected then return nil, projection_error end
        local approval_ready, approval_error = ensure_approval(step.status)
        if not approval_ready then return nil, approval_error end
        local waiting, waiting_error = project_wait(step.status)
        if not waiting then return nil, waiting_error end
        return step.progressed or #step.events > 0
    end

    local function compaction_outcome(result)
        local settlement = type(result) == "table" and result.settlement or nil
        if type(settlement) == "table" then return settlement.outcome end
        local raw = type(result) == "table" and result.result or nil
        if type(raw) ~= "table" then return false end
        if type(raw.outcome) == "string" then return raw.outcome end
        if raw.decision == "fits" then return "fits" end
        if raw.decision == "no_op" then return "no_op" end
        if raw.decision == "suppressed" then return "suppressed" end
        if raw.decision == "waiting_user" then return "waiting_user" end
        return false
    end

    local function resolve_automatic_preflight(result)
        local status = agent.loop:status()
        if status.compaction_preflight_state == nil
            or status.compaction_preflight_state == "idle"
        then
            return true
        end
        local settlement = result.settlement
        if type(settlement) == "table" and settlement.mode ~= "automatic" then
            return true
        end
        local outcome = compaction_outcome(result)
        if not outcome then
            return nil, failure(
                "CompactionActivityContract",
                "automatic compaction result has no typed preflight outcome"
            )
        end
        local resolved, resolution_error = coordinator_call(
            agent.loop,
            "resolve_compaction_preflight",
            "CompactionActivityFailure",
            "automatic compaction preflight resolution",
            {
                preflight_id = status.compaction_preflight_id,
                outcome = outcome,
                compaction_id = type(settlement) == "table"
                    and settlement.compaction_id or false,
                expected_context_generation = status.context_generation,
                expected_last_sequence = status.last_durable_sequence,
                expected_manifest_digest = status.active_view_manifest_ref,
                settlement = type(settlement) == "table" and settlement or false,
            }
        )
        if not resolved then return nil, resolution_error end
        return resolved
    end

    local function publish_compaction_result(result)
        local outcome = compaction_outcome(result)
        if outcome == "completed" then
            local raw = result.result
            return publish_status(
                "Compaction completed: " .. tostring(raw.compaction_id)
                    .. ", estimated benefit "
                    .. tostring(raw.benefit_tokens or "unknown") .. " tokens."
            )
        end
        if outcome == "no_op" or outcome == "fits" then
            return publish_status("Compaction made no change; the current view already fits.")
        end
        if outcome == "suppressed" then
            return publish_status("Automatic compaction is in cooldown; the old view was retained.")
        end
        if outcome == "waiting_user" then
            return publish_status("Compaction could not safely reduce the view; the old view was retained.")
        end
        if outcome == "cancelled" then
            return publish_status("Compaction cancelled; the old view was retained.")
        end
        if outcome == "unknown" then
            return publish_status("Compaction cancellation is unknown; no new view was activated.")
        end
        return nil, failure(
            "CompactionActivityContract",
            "compaction terminal result has no typed outcome"
        )
    end

    local function drive_compaction()
        if not agent or type(agent.compaction) ~= "table" then return false end
        local status = agent.compaction:status()
        if status.active ~= true then return false end
        local step, step_error = coordinator_call(
            agent.compaction,
            "poll",
            "CompactionActivityFailure",
            "compaction activity polling"
        )
        if not step then return nil, step_error end
        for _, event in ipairs(step.events) do
            local projected, projection_error
            if event.kind == "progress" then
                projected, projection_error = publish_status(
                    "Compaction retry started: "
                        .. tostring(event.request_id or "bound request") .. "."
                )
            elseif event.kind == "terminal" then
                projected, projection_error = publish_compaction_result(event.result)
                if projected then
                    projected, projection_error = resolve_automatic_preflight(
                        event.result
                    )
                end
            else
                return nil, failure(
                    "CompactionActivityContract",
                    "compaction owner returned an unknown event"
                )
            end
            if not projected then return nil, projection_error end
        end
        return step.progressed
    end

    local function drive_automatic_preflight()
        if not agent or type(agent.compaction) ~= "table" then return false end
        local status = agent.loop:status()
        if status.compaction_preflight_state ~= "pending" then return false end
        if agent.compaction:status().active == true
            or status.side_state ~= "idle"
            or status.active_request_id ~= false
            or status.active_tool_call_id ~= false
        then
            return false
        end
        local result, begin_error = coordinator_call(
            agent.compaction,
            "begin",
            "CompactionActivityFailure",
            "automatic compaction preflight",
            "automatic"
        )
        if not result then return nil, begin_error end
        if result.state == "active" then
            local published, publish_error = publish_status(
                "Automatic compaction started: "
                    .. tostring(result.compaction_id)
                    .. "; the pending Model request remains paused and cancellation is available."
            )
            if not published then return nil, publish_error end
            return true
        end
        if type(result.result) ~= "table" then
            return nil, failure(
                "CompactionActivityContract",
                "automatic compaction preflight returned neither an activity nor a result"
            )
        end
        local outcome = compaction_outcome(result)
        if outcome ~= "fits" and outcome ~= "no_op" then
            local published, publish_error = publish_compaction_result(result)
            if not published then return nil, publish_error end
        end
        local resolved, resolution_error = resolve_automatic_preflight(result)
        if not resolved then return nil, resolution_error end
        return true
    end

    local function status_lines()
        if not agent then
            local status = admitted_ports.chat.draft.status()
            return {
                "state: draft-ready",
                "workspace: " .. tostring(status.workspace),
                "context: new (not saved)",
                "model: " .. tostring(status.model),
                "permission: " .. tostring(status.permission),
            }
        end
        local status = agent.loop:status()
        local compact_status = agent.compaction:status()
        return {
            "state: " .. tostring(status.state),
            "turn: " .. tostring(status.turn_id),
            "context generation: " .. tostring(status.context_generation),
            "pending: " .. tostring(status.pending_kind),
            "automatic preflight: "
                .. tostring(status.compaction_preflight_state)
                .. " " .. tostring(status.compaction_preflight_id),
            "queue: " .. tostring(status.queue_count)
                .. "/" .. tostring(status.queue_maximum),
            "side: " .. tostring(status.side_state)
                .. " " .. tostring(status.active_side_id),
            "last outcome: " .. tostring(status.last_outcome),
            "compaction: " .. tostring(compact_status.state)
                .. " " .. tostring(compact_status.active_compaction_id),
            "compaction circuit: "
                .. tostring(compact_status.automatic_circuit_state)
                .. " failures="
                .. tostring(compact_status.automatic_failure_count),
        }
    end

    local function show_help(topic)
        local rendered, render_error = coordinator_function(
            admitted_ports.cli.render_help,
            "HelpRenderFailure",
            "chat help rendering",
            topic or "chat"
        )
        if not rendered then return nil, render_error end
        return publish({ kind = "notice", text = rendered })
    end

    local function show_details(diagnostic_id)
        if diagnostic_id == nil then
            diagnostic_id = diagnostic_order[#diagnostic_order]
            if diagnostic_id == nil then
                return publish_status("No interactive error details are available.")
            end
        end
        if approval and diagnostic_id == approval.action_id then
            return publish({
                kind = "details",
                id = approval.action_id,
                lines = approval.lines,
            })
        end
        local record = diagnostics_by_id[diagnostic_id]
        if not record then
            return nil, failure(
                "NotFound",
                "the requested interactive error instance is unavailable"
            )
        end
        local lines = {
            "instance: " .. record.id,
            "code: " .. record.code,
            "message: " .. record.message,
        }
        if record.suggestion then
            lines[#lines + 1] = "suggestion: " .. record.suggestion
        end
        return publish({ kind = "details", id = record.id, lines = lines })
    end

    local function cautious_word(value)
        if value == true then return "on" end
        if value == false then return "off" end
        return tostring(value)
    end

    local function publish_cautious(values, suffix)
        local effective = values.double_check_effective
        if effective == nil then effective = values.double_check end
        local text = "Cautious mode: default="
            .. cautious_word(values.double_check_default)
            .. " override=" .. cautious_word(values.double_check_override)
            .. " effective=" .. cautious_word(effective)
            .. "."
        if suffix then text = text .. " " .. suffix end
        return publish_status(text)
    end

    local function cautious_status()
        if agent then
            return coordinator_call(
                agent.settings,
                "status",
                "SessionUpdateFailure",
                "saved Session cautious status"
            )
        end
        return coordinator_function(
            admitted_ports.chat.draft.status,
            "SessionUpdateFailure",
            "unsaved Session cautious status"
        )
    end

    local function apply_cautious(request)
        local current, status_error = cautious_status()
        if not current then return nil, status_error end
        if request.operation == "status" then
            return publish_cautious(current)
        end
        local value
        if request.operation == "on" then
            value = true
        elseif request.operation == "off" then
            value = false
        elseif request.operation == "toggle" then
            local effective = current.double_check_effective
            if effective == nil then effective = current.double_check end
            if type(effective) ~= "boolean" then
                return nil, failure(
                    "SessionUpdateFailure",
                    "current cautious mode is not a boolean"
                )
            end
            value = not effective
        elseif request.operation == "reset" then
            value = "inherit"
        else
            return nil, failure(
                "InvalidSessionUpdate",
                "unknown cautious operation"
            )
        end
        if current.double_check_override == value then
            return publish_cautious(current)
        end
        local updated, update_error
        if agent then
            updated, update_error = coordinator_call(
                agent.settings,
                "update",
                "SessionUpdateFailure",
                "saved Session cautious update",
                { name = "DoubleCheckOverride", value = value }
            )
        else
            updated, update_error = coordinator_function(
                admitted_ports.chat.draft.update,
                "SessionUpdateFailure",
                "unsaved Session cautious update",
                { double_check_override = value }
            )
        end
        if not updated then return nil, update_error end
        return publish_cautious(
            updated,
            agent and "The change applies on the next turn."
                or "The change applies when the first turn starts."
        )
    end

    local function stage_and_apply(method, message)
        local staged, stage_error = coordinator_call(
            agent.session,
            "stage",
            "SessionInputFailure",
            "saved session draft staging",
            message,
            "terminal"
        )
        if not staged then return nil, stage_error end
        local result, action_error = coordinator_call(
            agent.session,
            method,
            "SessionInputFailure",
            "saved session " .. method
        )
        if not result then return nil, action_error end
        local shown, show_error = publish({ kind = "user", text = message })
        if not shown then return nil, show_error end
        if result.display_id then
            return publish({
                kind = "queue",
                id = result.display_id,
                text = "queued at position " .. tostring(result.position),
            })
        end
        if method == "steer" then
            steer_serial = steer_serial + 1
            return publish({
                kind = "steer",
                id = "steer-" .. tostring(steer_serial),
                text = "accepted for the active turn",
            })
        end
        if method == "side" then
            side_focus_id = result.side_id
            return publish_status(
                "Side request accepted: " .. tostring(result.side_id)
            )
        end
        return publish_status("Input accepted.")
    end

    local function list_queue()
        local projection, queue_error = coordinator_call(
            agent.session,
            "queue_list",
            "QueueActionFailure",
            "queue listing"
        )
        if not projection then return nil, queue_error end
        if projection.count == 0 then return publish_status("Queue is empty.") end
        for _, item in ipairs(projection.items) do
            local published, publish_error = publish({
                kind = "queue",
                id = item.display_id,
                text = item.text,
            })
            if not published then return nil, publish_error end
        end
        return true
    end

    local function publish_context_choices(result)
        if type(result) ~= "table"
            or result.action ~= "context-repl"
            or type(result.rows) ~= "table"
            or not valid_integer(result.total, 0)
            or not valid_integer(result.shown, 0)
            or result.shown ~= #result.rows
            or type(result.truncated) ~= "boolean"
        then
            return nil, failure(
                "ContextSwitchContract",
                "Context picker returned an invalid bounded catalog"
            )
        end
        local lines = {}
        local maximum_rows = math.min(#result.rows, 32)
        if maximum_rows == 0 then
            lines[1] = "No available Contexts were found."
        else
            for index = 1, maximum_rows do
                local row = result.rows[index]
                if type(row) ~= "table"
                    or type(row.hash16) ~= "string"
                    or type(row.display_name) ~= "string"
                    or type(row.logical_path) ~= "string"
                    or type(row.header_state) ~= "string"
                then
                    return nil, failure(
                        "ContextSwitchContract",
                        "Context picker returned an invalid catalog row"
                    )
                end
                lines[#lines + 1] = string.format(
                    "%2d %s [%-11s] %s - %s",
                    index,
                    safe_diagnostic(row.hash16, 16),
                    safe_diagnostic(row.header_state, 32),
                    safe_diagnostic(row.display_name, 128),
                    safe_diagnostic(row.logical_path, 256)
                )
            end
        end
        if result.truncated or maximum_rows < #result.rows then
            lines[#lines + 1] = "More Contexts exist; use context-repl full to inspect them."
        else
            lines[#lines + 1] = "Use .context <name-or-hash> to switch explicitly."
        end
        return publish({ kind = "details", id = "contexts", lines = lines })
    end

    local function switch_context(request)
        if request.selector == nil then
            local result, list_error = coordinator_call(
                admitted_ports.context_switch,
                "list",
                "ContextSwitchFailure",
                "bounded Context picker"
            )
            if not result then return nil, list_error end
            return publish_context_choices(result)
        end

        local current_status
        if agent then
            local runtime_status = agent.loop:status()
            local compact_status = agent.compaction:status()
            if runtime_status.state ~= "Idle" and runtime_status.state ~= "WaitingUser" then
                return nil, failure(
                    "InteractiveActionUnavailable",
                    "Context switching requires an idle or waiting Agent"
                )
            end
            if compact_status.active == true
                or runtime_status.compaction_preflight_state ~= "idle"
            then
                return nil, failure(
                    "InteractiveActionUnavailable",
                    "finish or cancel compaction before switching Context"
                )
            end
            if runtime_status.queue_count ~= 0 then
                return nil, failure(
                    "InteractiveActionUnavailable",
                    "clear or finish every queued item before switching Context"
                )
            end
            if runtime_status.side_state ~= "idle" then
                return nil, failure(
                    "InteractiveActionUnavailable",
                    "finish or cancel the side request before switching Context"
                )
            end
            if approval then
                return nil, failure(
                    "InteractiveActionUnavailable",
                    "resolve the pending approval before switching Context"
                )
            end
            current_status = agent.draft.status()
            local selector_hash = request.selector:match("^[0-9A-Fa-f]+$")
                and #request.selector == 16
                and request.selector:upper() or false
            if type(current_status) == "table"
                and selector_hash == current_status.context_hash
            then
                return publish_status("That Context is already active.")
            end
        end

        local preview, preview_error = coordinator_call(
            admitted_ports.context_switch,
            "preview",
            "ContextSwitchFailure",
            "Context switch preview",
            request.selector
        )
        if not preview then return nil, preview_error end
        if type(preview) ~= "table"
            or preview.kind ~= "continue-preview"
            or type(preview.logical_path) ~= "string"
            or type(preview.context_hash) ~= "string"
            or #preview.context_hash ~= 16
            or not preview.context_hash:match("^[0-9A-F]+$")
            or type(preview.recorded_workspace) ~= "string"
        then
            return nil, failure(
                "ContextSwitchContract",
                "Context switch preview is incomplete"
            )
        end
        if current_status and preview.logical_path == current_status.logical_path then
            return publish_status("That Context is already active.")
        end

        local closed, close_error = close_agent("context-switch")
        if not closed then
            deferred_failure = close_error or failure(
                "ContextLeaseUnknown",
                "the current Context could not be closed for switching"
            )
            lifecycle = "closing"
            return nil, deferred_failure
        end
        local activated, activation_error = coordinator_call(
            admitted_ports.context_switch,
            "activate",
            "ContextSwitchFailure",
            "exact Context switch activation",
            preview
        )
        if not activated then
            deferred_failure = activation_error or failure(
                "ContextSwitchFailure",
                "the selected Context changed after the current session closed"
            )
            lifecycle = "closing"
            return nil, deferred_failure
        end
        local next_agent = activated.agent
        local next_status = activated.status
        if type(next_agent) ~= "table"
            or type(next_agent.loop) ~= "table"
            or type(next_agent.driver) ~= "table"
            or type(next_agent.session) ~= "table"
            or type(next_agent.settings) ~= "table"
            or type(next_agent.settings.status) ~= "function"
            or type(next_agent.settings.update) ~= "function"
            or type(next_agent.tools) ~= "table"
            or type(next_agent.compaction) ~= "table"
            or type(next_agent.draft) ~= "table"
            or type(next_status) ~= "table"
            or next_status.logical_path ~= preview.logical_path
            or next_status.context_hash ~= preview.context_hash
        then
            deferred_failure = failure(
                "ContextSwitchContract",
                "Context switch activation did not preserve the previewed target"
            )
            lifecycle = "closing"
            return nil, deferred_failure
        end
        agent = next_agent
        approval = false
        assistant_draft = ""
        side_draft = ""
        side_draft_id = false
        side_focus_id = false
        last_wait_key = false
        tool_ids = {}
        return publish_status(
            "Context switched: " .. tostring(next_status.display_name)
                .. " [" .. tostring(next_status.context_hash) .. "]"
                .. " workspace=" .. tostring(next_status.workspace)
        )
    end

    local function route_agent_action(request)
        local compact_status = agent.compaction:status()
        local runtime_status = agent.loop:status()
        local compaction_busy = compact_status.active == true
            or runtime_status.compaction_preflight_state == "pending"
            or runtime_status.compaction_preflight_state == "settled"
            or runtime_status.compaction_preflight_state == "blocked"
            or runtime_status.pending_kind == "compaction-preflight"
        if compaction_busy
            and request.id ~= "cancel"
            and request.id ~= "status-chat"
            and request.id ~= "help-chat"
        then
            return nil, failure(
                "CompactionBusy",
                "wait for compaction to finish or cancel it before this action"
            )
        end
        if request.id == "compact-manual" then
            local result, action_error = coordinator_call(
                agent.compaction,
                "begin",
                "CompactionActionFailure",
                "manual compaction",
                "manual"
            )
            if not result then return nil, action_error end
            if result.state == "active" then
                return publish_status(
                    "Compaction started: " .. tostring(result.compaction_id)
                        .. "; source facts remain intact and cancellation is available."
                )
            end
            return publish_compaction_result(result)
        end
        if request.id == "queue-add" then
            return stage_and_apply("submit", request.message)
        end
        if request.id == "steer" then
            return stage_and_apply("steer", request.message)
        end
        if request.id == "side" then
            return stage_and_apply("side", request.message)
        end
        if request.id == "queue-list" then return list_queue() end
        if request.id == "queue-delete" then
            local result, action_error = coordinator_call(
                agent.session,
                "queue_drop",
                "QueueActionFailure",
                "queue deletion",
                request.queue_id,
                "user-drop"
            )
            if not result then return nil, action_error end
            return publish_status("Queue item deleted.")
        end
        if request.id == "queue-edit" then
            local result, action_error = coordinator_call(
                agent.session,
                "queue_edit",
                "QueueActionFailure",
                "queue edit",
                request.queue_id,
                request.message
            )
            if not result then return nil, action_error end
            return publish_status("Queue item edited.")
        end
        if request.id == "queue-move" then
            local result, action_error = coordinator_call(
                agent.session,
                "queue_move",
                "QueueActionFailure",
                "queue move",
                request.from,
                request.to
            )
            if not result then return nil, action_error end
            return publish_status("Queue item moved.")
        end
        if request.id == "queue-clear" then
            local result, action_error = coordinator_call(
                agent.session,
                "queue_clear",
                "QueueActionFailure",
                "queue clear",
                "user-clear"
            )
            if not result then return nil, action_error end
            return publish_status("Queue cleared.")
        end
        if request.id == "cancel" then
            if compact_status.active == true then
                local result, action_error = coordinator_call(
                    agent.compaction,
                    "cancel",
                    "CancelFailure",
                    "compaction cancellation",
                    "user-cancel"
                )
                if not result then return nil, action_error end
                if result.cancel_pending == true then
                    return publish_status("Compaction cancellation is pending.")
                end
                local published, publish_error = publish_compaction_result(result)
                if not published then return nil, publish_error end
                return resolve_automatic_preflight(result)
            end
            local current = agent.loop:status()
            if side_focus_id ~= false
                and current.active_side_id == side_focus_id
                and current.side_state == "cancelling"
            then
                return publish_status("Side cancellation is already pending.")
            end
            if side_focus_id ~= false
                and current.active_side_id == side_focus_id
                and current.side_state == "active"
            then
                local result, action_error = coordinator_call(
                    agent.loop,
                    "cancel_side",
                    "CancelFailure",
                    "side cancellation",
                    {
                        side_id = side_focus_id,
                        reason = "user-cancel",
                        expected_context_generation = current.context_generation,
                        expected_turn_id = current.turn_id,
                    }
                )
                if not result then return nil, action_error end
                if result.cancel_pending ~= true then side_focus_id = false end
                return publish_status("Side cancellation requested.")
            end
            local result, action_error = coordinator_call(
                agent.loop,
                "cancel",
                "CancelFailure",
                "Agent cancellation",
                "user-cancel"
            )
            if not result then return nil, action_error end
            return publish_status("Cancellation requested.")
        end
        if request.id == "status-chat" then
            return publish({ kind = "details", id = "status", lines = status_lines() })
        end
        if request.id == "help-chat" then return show_help(request.topic) end
        if request.id == "multiline" then
            return publish_status("Use Shift+Enter or embedded newlines, then submit.")
        end
        return nil, failure(
            "InteractiveActionUnavailable",
            "this registered chat action is not attached to the active coordinator"
        )
    end

    local function start_first_agent(message)
        local constructed, agent_error = coordinator_function(
            admitted_ports.agent_factory,
            "AgentCompositionFailure",
            "published production Agent construction",
            message,
            "terminal"
        )
        if not constructed then return nil, agent_error end
        if type(constructed) ~= "table"
            or type(constructed.loop) ~= "table"
            or type(constructed.driver) ~= "table"
            or type(constructed.session) ~= "table"
            or type(constructed.settings) ~= "table"
            or type(constructed.settings.status) ~= "function"
            or type(constructed.settings.update) ~= "function"
            or type(constructed.tools) ~= "table"
            or type(constructed.compaction) ~= "table"
            or type(constructed.draft) ~= "table"
        then
            return nil, failure(
                "AgentCompositionFailure",
                "published production Agent is incomplete"
            )
        end
        agent = constructed
        local published, publish_error = publish({ kind = "user", text = message })
        if not published then return nil, publish_error end
        local status = agent.draft.status()
        published, publish_error = publish_status(
            "Context saved: " .. tostring(status.display_name)
                .. " [" .. tostring(status.context_hash) .. "]"
        )
        if not published then return nil, publish_error end
        return true
    end

    local function record_approval(answer)
        local envelope, envelope_error = coordinator_function(
            agent.tools.record_approval,
            "ApprovalRecordFailure",
            "local Tool approval recording",
            approval.tool_call_id,
            approval.review_verdict,
            approval.action_id,
            answer == "allow" and "approve" or "reject"
        )
        if not envelope then return nil, envelope_error end
        local resolved, resolve_error = coordinator_call(
            agent.loop,
            "resolve_approval",
            "ApprovalResolutionFailure",
            "Runtime Tool approval resolution",
            envelope
        )
        if not resolved then return nil, resolve_error end
        local action_id = approval.action_id
        approval = false
        return publish({
            kind = "action",
            id = action_id,
            text = answer == "allow" and "allowed once" or "denied",
        })
    end

    local function route_approval_line(source)
        local normalized = trim_coordinator_line(source)
        if normalized == "" then return record_approval("deny") end
        local action_id = normalized:match("^allow%s+(%S+)%s+once$")
        if action_id then
            if action_id ~= approval.action_id then
                return nil, failure("ApprovalStale", "approval action identity is stale")
            end
            return record_approval("allow")
        end
        action_id = normalized:match("^deny%s+(%S+)$")
        if action_id then
            if action_id ~= approval.action_id then
                return nil, failure("ApprovalStale", "approval action identity is stale")
            end
            return record_approval("deny")
        end
        action_id = normalized:match("^details%s+(%S+)$")
        if action_id then
            if action_id ~= approval.action_id then
                return nil, failure("ApprovalStale", "approval action identity is stale")
            end
            return publish({
                kind = "details",
                id = approval.action_id,
                lines = approval.lines,
            })
        end
        return nil, failure(
            "ApprovalSelectionRequired",
            "use allow <action-id> once, deny <action-id>, or details <action-id>"
        )
    end

    local function parse_chat(source)
        local request, parse_error = coordinator_function(
            admitted_ports.cli.parse_chat,
            "ChatParseFailure",
            "chat semantic parsing",
            source,
            admitted_ports.facts
        )
        if not request then return nil, parse_error end
        return request
    end

    local function route_line(source)
        local normalized = trim_coordinator_line(source)
        if approval and normalized:sub(1, 1) ~= "." then
            return route_approval_line(source)
        end
        if normalized == "" then return true end
        local request, parse_error = parse_chat(source)
        if not request then return nil, parse_error end
        if request.id == "quit" then
            lifecycle = "closing"
            return publish_status("Closing the current session.")
        end
        if request.id == "status-chat" then
            return publish({ kind = "details", id = "status", lines = status_lines() })
        end
        if request.id == "help-chat" then return show_help(request.topic) end
        if request.id == "details" then return show_details(request.error_id) end
        if request.id == "cautious" then return apply_cautious(request) end
        if request.id == "select-context" then return switch_context(request) end
        if not agent then
            if request.id == "queue-add" then
                return start_first_agent(request.message)
            end
            return nil, failure(
                "NoSavedContext",
                "send the first main message before using this chat action"
            )
        end
        return route_agent_action(request)
    end

    local function handle_submission(intent)
        if input_draft == "" and intent ~= "submit-or-queue" then
            return nil, failure("DraftEmpty", "the selected input lane has no draft")
        end
        local result, action_error
        if intent == "submit-or-queue" then
            result, action_error = route_line(input_draft)
        elseif not agent then
            result, action_error = nil, failure(
                "NoSavedContext",
                "send the first main message before using a busy input lane"
            )
        elseif intent == "steer" then
            result, action_error = stage_and_apply("steer", input_draft)
        else
            result, action_error = stage_and_apply("side", input_draft)
        end
        if result then input_draft = "" end
        prompt_needed = lifecycle ~= "closing"
        return result, action_error
    end

    local function handle_cancel()
        if input_draft ~= "" then
            input_draft = ""
            prompt_needed = true
            return publish_status("Input draft cleared.")
        end
        if approval then return record_approval("deny") end
        if not agent then return publish_status("Nothing to cancel.") end
        return route_agent_action({ id = "cancel" })
    end

    local function handle_terminal_event(event)
        if type(event) ~= "table" or type(event.kind) ~= "string" then
            return nil, failure(
                "TerminalContract",
                "ApplicationCoordinator received an invalid terminal event"
            )
        end
        if event.kind == "io_terminal" then
            terminal_ended = true
            terminal_outcome = event.outcome
            lifecycle = "closing"
            return true
        end
        if event.kind ~= "user_action" then
            return nil, failure(
                "TerminalContract",
                "ApplicationCoordinator received an unknown terminal event"
            )
        end
        if event.action == "text" then
            if type(event.text) ~= "string"
                or #input_draft + #event.text > admitted.maximum_draft_bytes
            then
                return nil, failure("DraftLimit", "terminal draft exceeds its byte limit")
            end
            input_draft = input_draft .. event.text
            return true
        end
        if event.action == "newline" then
            if #input_draft + 1 > admitted.maximum_draft_bytes then
                return nil, failure("DraftLimit", "terminal draft exceeds its byte limit")
            end
            input_draft = input_draft .. "\n"
            return true
        end
        if event.action == "submit-or-queue"
            or event.action == "steer"
            or event.action == "side"
        then
            return handle_submission(event.action)
        end
        if event.action == "cancel" then return handle_cancel() end
        if event.action == "eof" then
            terminal_ended = true
            terminal_outcome = "completed"
            lifecycle = "closing"
            return true
        end
        return nil, failure(
            "TerminalContract",
            "ApplicationCoordinator received an unknown input action"
        )
    end

    local function close_terminal()
        if not terminal_started then return true end
        local observed_now = last_now or 0
        if not terminal_ended then
            pcall(admitted_ports.terminal.cancel, admitted_ports.terminal, observed_now)
            local polled, events = pcall(
                admitted_ports.terminal.poll,
                admitted_ports.terminal,
                observed_now,
                admitted.terminal_poll_events
            )
            if polled and type(events) == "table" then
                for _, event in ipairs(events) do
                    if event.kind == "io_terminal" then
                        terminal_ended = true
                        terminal_outcome = event.outcome
                    end
                end
            end
        end
        if terminal_ended then
            pcall(admitted_ports.terminal.join, admitted_ports.terminal, observed_now)
        end
        pcall(admitted_ports.terminal.restore, admitted_ports.terminal)
        local closed, close_result = pcall(
            admitted_ports.terminal.close,
            admitted_ports.terminal
        )
        terminal_started = false
        if not closed or close_result ~= true then
            return nil, failure(
                "TerminalRestoreFailure",
                "terminal state could not be restored and closed"
            )
        end
        return true
    end

    close_agent = function(reason)
        if not agent then
            return coordinator_call(
                admitted_ports.chat.draft,
                "close",
                "SessionCloseFailure",
                "unsaved chat close"
            )
        end
        local compact_status = agent.compaction:status()
        if compact_status.active == true then
            local cancelling, cancel_error = coordinator_call(
                agent.compaction,
                "close",
                "SessionCloseFailure",
                "compaction close",
                reason
            )
            if not cancelling then return nil, cancel_error end
            for _ = 1, admitted.close_poll_steps do
                compact_status = agent.compaction:status()
                if compact_status.active ~= true then break end
                local progressed, progress_error = drive_compaction()
                if progressed == nil then return nil, progress_error end
                if not progressed then
                    local waited, wait_error = coordinator_function(
                        admitted_ports.idle_wait,
                        "IdleWaitFailure",
                        "compaction close wait",
                        admitted.idle_wait_ms
                    )
                    if not waited then return nil, wait_error end
                end
            end
            if agent.compaction:status().active == true then
                return nil, failure(
                    "SessionCloseTimeout",
                    "compaction did not reach terminal close truth"
                )
            end
            local closed_compaction, close_error = coordinator_call(
                agent.compaction,
                "close",
                "SessionCloseFailure",
                "compaction owner close",
                reason
            )
            if closed_compaction == nil then return nil, close_error end
        else
            local closed_compaction, close_error = coordinator_call(
                agent.compaction,
                "close",
                "SessionCloseFailure",
                "compaction owner close",
                reason
            )
            if closed_compaction == nil then return nil, close_error end
        end
        local closed, close_error = coordinator_call(
            agent.session,
            "close",
            "SessionCloseFailure",
            "saved Agent session close",
            reason
        )
        if not closed then return nil, close_error end
        for _ = 1, admitted.close_poll_steps do
            local status = agent.loop:status()
            if status.state == "Closing" then break end
            local progressed, progress_error = drive_agent()
            if progressed == nil then return nil, progress_error end
            if not progressed then
                local waited, wait_error = coordinator_function(
                    admitted_ports.idle_wait,
                    "IdleWaitFailure",
                    "coordinator close wait",
                    admitted.idle_wait_ms
                )
                if not waited then return nil, wait_error end
            end
        end
        if agent.loop:status().state ~= "Closing" then
            return nil, failure(
                "SessionCloseTimeout",
                "Agent activities did not reach terminal close truth"
            )
        end
        return coordinator_call(
            agent.draft,
            "close",
            "SessionCloseFailure",
            "durable Context writer close"
        )
    end

    local function finish_run(primary_error)
        local closed_agent, agent_error = close_agent("application-close")
        local closed_terminal, terminal_error = close_terminal()
        lifecycle = "closed"
        if primary_error then return nil, primary_error end
        if not closed_agent then return nil, agent_error end
        if not closed_terminal then return nil, terminal_error end
        if terminal_outcome == "failed" or terminal_outcome == "unknown" then
            return nil, failure(
                "TerminalFailure",
                "interactive terminal ended without a successful outcome"
            )
        end
        return readonly({
            kind = "interactive-chat",
            outcome = "success",
            terminal_outcome = terminal_outcome or "cancelled-by-close",
            context_saved = agent ~= false,
        }, "interactive chat result")
    end

    ---Runs until a typed quit or terminal outcome, then closes in dependency order.
    -- @return table|nil result Immutable successful interactive result.
    -- @return table|nil err Structured terminal, Agent, renderer, or close failure.
    function coordinator:run()
        if lifecycle ~= "created" then
            return nil, failure(
                "CoordinatorState",
                "ApplicationCoordinator can run exactly once"
            )
        end
        lifecycle = "running"
        local started_view, view_error = coordinator_call(
            admitted_ports.view,
            "startup",
            "RendererFailure",
            "startup view publication",
            admitted_ports.chat.status
        )
        if not started_view then return finish_run(view_error) end
        local observed_now, clock_error = now()
        if not observed_now then return finish_run(clock_error) end
        local started_terminal, terminal_error = coordinator_call(
            admitted_ports.terminal,
            "start",
            "TerminalStartFailure",
            "terminal input start",
            observed_now
        )
        if not started_terminal then return finish_run(terminal_error) end
        terminal_started = true

        while lifecycle == "running" do
            observed_now, clock_error = now()
            if not observed_now then return finish_run(clock_error) end
            local events, poll_error = coordinator_call(
                admitted_ports.terminal,
                "poll",
                "TerminalPollFailure",
                "terminal input polling",
                observed_now,
                admitted.terminal_poll_events
            )
            if not events then return finish_run(poll_error) end
            if type(events) ~= "table" then
                return finish_run(failure(
                    "TerminalContract",
                    "terminal poll did not return an event array"
                ))
            end
            local progressed = #events > 0
            for _, event in ipairs(events) do
                local handled, handle_error = handle_terminal_event(event)
                if not handled then
                    local displayed, display_error = publish_error(handle_error)
                    if not displayed then return finish_run(display_error) end
                    prompt_needed = lifecycle ~= "closing"
                end
                if lifecycle == "closing" then break end
            end
            if lifecycle == "running" and agent then
                local preflight_progress, preflight_error
                    = drive_automatic_preflight()
                if preflight_progress == nil then
                    return finish_run(preflight_error)
                end
                progressed = progressed or preflight_progress
                local compact_progress, compact_error = drive_compaction()
                if compact_progress == nil then return finish_run(compact_error) end
                progressed = progressed or compact_progress
                if agent.compaction:status().active ~= true then
                    local agent_progress, agent_error = drive_agent()
                    if agent_progress == nil then return finish_run(agent_error) end
                    progressed = progressed or agent_progress
                end
            end
            if lifecycle == "running" and prompt_needed then
                local focus = approval and "approval" or "chat"
                local prompted, prompt_error = show_prompt(focus)
                if not prompted then return finish_run(prompt_error) end
            end
            if lifecycle == "running" and not progressed then
                local waited, wait_error = coordinator_function(
                    admitted_ports.idle_wait,
                    "IdleWaitFailure",
                    "coordinator idle wait",
                    admitted.idle_wait_ms
                )
                if not waited then return finish_run(wait_error) end
            end
        end
        return finish_run(deferred_failure or nil)
    end

    function coordinator:status()
        return readonly({
            lifecycle = lifecycle,
            terminal_started = terminal_started,
            terminal_ended = terminal_ended,
            terminal_outcome = terminal_outcome,
            context_saved = agent ~= false,
            draft_bytes = #input_draft,
            approval_action_id = approval and approval.action_id or false,
            diagnostic_count = #diagnostic_order,
        }, "ApplicationCoordinator status")
    end

    return readonly(coordinator, "ApplicationCoordinator")
end

local function production_chat_view(composed, runtime)
    if type(runtime.stdout) ~= "function"
        and (type(runtime.stdout) ~= "table"
            or type(runtime.stdout.write) ~= "function")
    then
        return nil, failure(
            "InvalidCoordinatorPorts",
            "interactive stdout writer is unavailable"
        )
    end
    local tui = require("tui")
    local enhanced_keys = composed.identity.os == "windows"
    local renderer, renderer_error = tui.new({
        width = 80,
        capabilities = {
            ansi = false,
            color = false,
            unicode = false,
            keys = {
                Enter = true,
                ["Ctrl+Enter"] = enhanced_keys,
                ["Shift+Enter"] = enhanced_keys,
                ["Alt+Enter"] = enhanced_keys,
                Esc = true,
            },
        },
        maximum_block_bytes = 524288,
        maximum_line_bytes = 262144,
        maximum_id_bytes = 256,
        writer = runtime.stdout,
    })
    if not renderer then return nil, renderer_error end
    local view = {}

    local function write_rendered(bytes)
        if not write_direct(runtime.stdout, bytes) then
            return nil, failure(
                "BrokenStdout",
                "interactive transcript output could not be completed"
            )
        end
        return true
    end

    ---Writes the independent ASCII-first startup fields before input starts.
    function view:startup(status)
        local existing = status.durable == true
        local rendered, render_error = renderer.render_startup({
            version = "0.1.0",
            work_directory = status.workspace,
            data_root = composed.layout.data_root,
            config_status = "valid",
            context = existing and status.display_name or "new (not saved)",
            context_hash = existing and status.context_hash or nil,
            model = status.model,
            permission = status.permission,
            double_check = status.double_check,
        }, {
            slogan = true,
            version = true,
            work_directory = true,
            data_root = true,
            config_status = true,
            context = true,
            context_hash = existing,
            model = true,
            permission = true,
            double_check = true,
            status_hint = true,
        }, "chat")
        if not rendered then return nil, render_error end
        return write_rendered(rendered)
    end

    ---Appends one validated complete semantic transcript block.
    function view:publish(block)
        local rendered, render_error = renderer.append(block)
        if not rendered then return nil, render_error end
        return true
    end

    ---Writes one plain focus prompt without assuming ANSI or cursor movement.
    function view:prompt(focus)
        local rendered, render_error = renderer.render_prompt(focus)
        if not rendered then return nil, render_error end
        return write_rendered(rendered)
    end

    return readonly(view, "production chat view")
end

function M.new_context_switcher(initial_composed, runtime, dependencies)
    dependencies = dependencies or {}
    if type(initial_composed) ~= "table"
        or type(initial_composed.application) ~= "table"
        or type(initial_composed.application.dispatch) ~= "function"
        or type(initial_composed.application.preview_continue) ~= "function"
        or type(runtime) ~= "table"
        or type(dependencies) ~= "table"
    then
        return nil, failure(
            "InvalidContextSwitchPorts",
            "production Context switch dependencies are incomplete"
        )
    end
    for key in pairs(dependencies) do
        if key ~= "compose" and key ~= "start_agent" then
            return nil, failure(
                "InvalidContextSwitchPorts",
                "production Context switch dependencies are ambiguous"
            )
        end
    end
    local compose = dependencies.compose or M.compose_runtime
    local start_agent = dependencies.start_agent or M.start_published_agent
    if type(compose) ~= "function" or type(start_agent) ~= "function" then
        return nil, failure(
            "InvalidContextSwitchPorts",
            "production Context switch factories are unavailable"
        )
    end
    local current = initial_composed
    local switcher = {}

    function switcher:list()
        local called, result, result_error = pcall(
            current.application.dispatch,
            { id = "context-repl", view = "recent" }
        )
        if not called then
            return nil, failure(
                "ContextSwitchFailure",
                "the bounded Context catalog raised an exception"
            )
        end
        if not result then return nil, result_error end
        if result.action ~= "context-repl" or type(result.rows) ~= "table" then
            return nil, failure(
                result.error_code or "ContextSwitchFailure",
                "the bounded Context catalog is unavailable"
            )
        end
        return result
    end

    function switcher:preview(selector)
        local called, result, result_error = pcall(
            current.application.preview_continue,
            selector
        )
        if not called then
            return nil, failure(
                "ContextSwitchFailure",
                "Context switch preview raised an exception"
            )
        end
        return result, result_error
    end

    function switcher:activate(preview)
        if type(preview) ~= "table"
            or preview.kind ~= "continue-preview"
            or type(preview.context_hash) ~= "string"
            or type(preview.logical_path) ~= "string"
        then
            return nil, failure(
                "ContextSwitchContract",
                "exact Context activation requires a verified preview"
            )
        end
        local composed_call, next_composed, composition_error = pcall(compose, runtime)
        if not composed_call then
            return nil, failure(
                "ContextSwitchFailure",
                "replacement Runtime composition raised an exception"
            )
        end
        if not next_composed then return nil, composition_error end
        if type(next_composed) ~= "table"
            or type(next_composed.application) ~= "table"
            or type(next_composed.application.dispatch) ~= "function"
            or type(next_composed.application.preview_continue) ~= "function"
        then
            return nil, failure(
                "ContextSwitchContract",
                "replacement Runtime composition is incomplete"
            )
        end
        local dispatched, chat, dispatch_error = pcall(
            next_composed.application.dispatch,
            { id = "continue", selector = preview.context_hash }
        )
        if not dispatched then
            return nil, failure(
                "ContextSwitchFailure",
                "exact Context activation raised an exception"
            )
        end
        if not chat then return nil, dispatch_error end
        if type(chat) ~= "table"
            or type(chat.status) ~= "table"
            or type(chat.draft) ~= "table"
            or type(chat.draft.close) ~= "function"
        then
            return nil, failure(
                "ContextSwitchContract",
                "exact Context activation returned an incomplete chat"
            )
        end
        local function release_chat_writer(message)
            local close_called, closed, close_error = pcall(chat.draft.close)
            if not close_called or closed == nil then
                return nil, close_error or failure("ContextLeaseUnknown", message)
            end
            return true
        end
        if chat.status.logical_path ~= preview.logical_path
            or chat.status.context_hash ~= preview.context_hash
        then
            local released, release_error = release_chat_writer(
                "changed Context activation writer release is unknown"
            )
            if not released then return nil, release_error end
            return nil, failure(
                "TargetChanged",
                "the selected Context changed after the prior session closed"
            )
        end
        local started, next_agent, agent_error = pcall(
            start_agent,
            next_composed,
            chat,
            CONTINUATION_INSTRUCTION,
            "context-switch"
        )
        if not started then
            local released, release_error = release_chat_writer(
                "failed Context activation writer release is unknown"
            )
            if not released then return nil, release_error end
            return nil, failure(
                "ContextSwitchFailure",
                "replacement Agent composition raised an exception"
            )
        end
        if not next_agent then
            local released, release_error = release_chat_writer(
                "failed replacement Agent writer release is unknown"
            )
            if not released then return nil, release_error end
            return nil, agent_error
        end
        if type(next_agent) ~= "table"
            or type(next_agent.loop) ~= "table"
            or type(next_agent.driver) ~= "table"
            or type(next_agent.session) ~= "table"
            or type(next_agent.settings) ~= "table"
            or type(next_agent.settings.status) ~= "function"
            or type(next_agent.settings.update) ~= "function"
            or type(next_agent.tools) ~= "table"
            or type(next_agent.compaction) ~= "table"
            or type(next_agent.draft) ~= "table"
        then
            local released, release_error = release_chat_writer(
                "incomplete replacement Agent writer release is unknown"
            )
            if not released then return nil, release_error end
            return nil, failure(
                "ContextSwitchContract",
                "replacement Agent composition is incomplete"
            )
        end
        current = next_composed
        return readonly({
            agent = next_agent,
            status = chat.status,
        }, "activated Context switch")
    end

    return readonly(switcher, "production Context switch port")
end

---Runs one production chat through the terminal ApplicationCoordinator.
-- The plain cooked path requires no ANSI, raw keyboard mode, Unicode console,
-- terminal size probe, or cursor movement.  Windows modifier keys are exposed
-- only when the native console adapter reports their semantic events; every
-- action retains its registry-generated text fallback.
-- @param composed table Production runtime composition.
-- @param chat table Ready run-chat or continue-chat bootstrap result.
-- @param runtime table CLI invocation ports and exact fd facts.
-- @param initial_agent table|nil Already composed idle Agent for continue-chat.
-- @return table|nil result Immutable interactive outcome.
-- @return table|nil err Structured composition, runtime, or close failure.
function M.run_interactive_chat(composed, chat, runtime, initial_agent)
    if type(composed) ~= "table"
        or type(composed.backend) ~= "table"
        or type(composed.backend.new_terminal) ~= "function"
        or type(composed.backend.clock_port) ~= "table"
        or type(composed.backend.clock_port.monotonic_now) ~= "function"
        or type(composed.backend.clock_port.sleep_ms) ~= "function"
        or type(runtime) ~= "table"
        or type(runtime.cli) ~= "table"
        or type(runtime.stdio_facts) ~= "table"
        or type(chat) ~= "table"
        or (chat.kind ~= "run-chat" and chat.kind ~= "continue-chat")
        or chat.outcome ~= "ready"
        or (chat.kind == "continue-chat" and type(initial_agent) ~= "table")
    then
        return nil, failure(
            "InvalidCoordinatorPorts",
            "a ready production chat and terminal runtime are required"
        )
    end
    local function fail_before_coordinator(primary_error)
        if initial_agent then
            pcall(initial_agent.compaction.close, initial_agent.compaction,
                "interactive-composition-failed")
            pcall(initial_agent.session.close, initial_agent.session,
                "interactive-composition-failed")
            local called, closed, close_error = pcall(initial_agent.draft.close)
            if not called or closed == nil then
                return nil, close_error or failure(
                    "ContextLeaseUnknown",
                    "existing Context writer release is unknown"
                )
            end
        end
        return nil, primary_error
    end
    local terminal_port, terminal_error = composed.backend.new_terminal("cooked")
    if not terminal_port then return fail_before_coordinator(terminal_error) end
    local view, view_error = production_chat_view(composed, runtime)
    if not view then return fail_before_coordinator(view_error) end
    local context_switch, switch_error = M.new_context_switcher(composed, runtime)
    if not context_switch then return fail_before_coordinator(switch_error) end
    local coordinator, coordinator_error = M.new_application_coordinator({
        terminal = terminal_port,
        clock = { now = composed.backend.clock_port.monotonic_now },
        idle_wait = composed.backend.clock_port.sleep_ms,
        cli = runtime.cli,
        facts = runtime.stdio_facts,
        view = view,
        chat = chat,
        context_switch = context_switch,
        initial_agent = initial_agent,
        agent_factory = function(message, source)
            return M.start_published_agent(composed, chat, message, source)
        end,
    }, {
        close_poll_steps = 1024,
        idle_wait_ms = 10,
        maximum_assistant_bytes = MODEL_ADAPTER_OPTIONS.maximum_text_bytes,
        maximum_draft_bytes = 16384,
        terminal_poll_events = 128,
    })
    if not coordinator then return fail_before_coordinator(coordinator_error) end
    return coordinator:run()
end

local function hex_bytes(value)
    local output = {}
    for index = 1, #value do
        output[index] = string.format("%02x", value:byte(index))
    end
    return table.concat(output)
end

local function model_setup_diagnostic(value, maximum_source_bytes)
    return ascii_diagnostic(value, maximum_source_bytes)
end

local function model_setup_sections(values)
    local model_values = {
        Enabled = values.enabled,
        Protocol = values.protocol,
        Endpoint = values.endpoint,
        RemoteModel = values.remote_model,
    }
    if values.key ~= "" then model_values.Key = values.key end
    return {
        {
            name = "General",
            values = {
                SchemaVersion = "0.1.0",
                StartupSelfTest = "off",
            },
        },
        {
            name = "Permission.Std",
            values = {
                Read = "allow",
                Write = "confirm",
                Delete = "confirm",
                Shell = "confirm",
                OutsideWorkspace = "confirm",
            },
        },
        {
            name = "Model." .. values.name,
            values = model_values,
        },
    }
end

local function model_setup_changes(values)
    local section = "Model." .. values.name
    local changes = {
        { section = section, key = "Enabled", value = values.enabled },
        { section = section, key = "Protocol", value = values.protocol },
        { section = section, key = "Endpoint", value = values.endpoint },
        { section = section, key = "RemoteModel", value = values.remote_model },
    }
    if values.key ~= "" then
        changes[#changes + 1] = { section = section, key = "Key", value = values.key }
    end
    return changes
end

local function new_model_setup_input(composed, runtime)
    local text = require("text")
    local active = false
    local active_mode = false
    local terminal_ended = false
    local input = {}

    local function output(bytes)
        if not write_direct(runtime.stdout, bytes) then
            return nil, failure("BrokenStdout", "Model setup output could not be completed")
        end
        return true
    end

    local function now()
        local called, value = pcall(composed.backend.clock_port.monotonic_now)
        if not called or not valid_integer(value, 0) then
            return nil, failure("MonotonicClockDegraded", "Model setup clock is unavailable")
        end
        return value
    end

    local function close_active()
        if not active then return true end
        local observed_now, clock_error = now()
        if not observed_now then return nil, clock_error end
        local primary_error
        if not terminal_ended then
            local cancel_called, cancelled = pcall(active.cancel, active, observed_now)
            if not cancel_called or cancelled ~= true then
                primary_error = failure(
                    "TerminalFailure",
                    "Model setup input cancellation could not be requested"
                )
            else
                for _ = 1, 1024 do
                    local poll_called, events = pcall(active.poll, active, observed_now, 128)
                    if not poll_called or type(events) ~= "table" then
                        primary_error = primary_error or failure(
                            "TerminalFailure",
                            "Model setup cancellation outcome could not be observed"
                        )
                        break
                    end
                    for _, event in ipairs(events) do
                        if type(event) ~= "table" then
                            primary_error = primary_error or failure(
                                "TerminalFailure",
                                "Model setup cancellation emitted an invalid event"
                            )
                            break
                        end
                        if event.kind == "io_terminal" then
                            terminal_ended = true
                            break
                        end
                    end
                    if terminal_ended or primary_error then break end
                    local next_now, next_error = now()
                    if not next_now then
                        primary_error = primary_error or next_error
                        break
                    end
                    observed_now = next_now
                    local slept, sleep_result = pcall(
                        composed.backend.clock_port.sleep_ms,
                        10
                    )
                    if not slept or sleep_result == false then
                        primary_error = primary_error or failure(
                            "IdleWaitFailure",
                            "Model setup cancellation wait failed"
                        )
                        break
                    end
                end
                if not terminal_ended then
                    primary_error = primary_error or failure(
                        "TerminalFailure",
                        "Model setup cancellation did not reach terminal truth"
                    )
                end
            end
        end
        local joined, join_result = pcall(
            active.join,
            active,
            observed_now <= math.maxinteger - 5000 and observed_now + 5000
                or observed_now
        )
        if not joined or type(join_result) ~= "table" then
            primary_error = primary_error or failure(
                "TerminalFailure",
                "Model setup input could not be joined"
            )
        end
        local close_called, closed = pcall(active.close, active)
        if not close_called or closed ~= true then
            primary_error = primary_error or failure(
                "TerminalFailure",
                "Model setup terminal state could not be restored"
            )
        end
        active = false
        active_mode = false
        terminal_ended = false
        if primary_error then return nil, primary_error end
        return true
    end

    local function activate(mode)
        if active_mode == mode then return true end
        local closed, close_error = close_active()
        if not closed then return nil, close_error end
        local terminal, terminal_error = composed.backend.new_terminal(mode)
        if not terminal then return nil, terminal_error end
        local observed_now, clock_error = now()
        if not observed_now then return nil, clock_error end
        local called, started = pcall(terminal.start, terminal, observed_now)
        if not called or started ~= true then
            pcall(terminal.close, terminal)
            return nil, failure(
                "TerminalStartFailure",
                "Model setup terminal input could not start"
            )
        end
        active = terminal
        active_mode = mode
        terminal_ended = false
        return true
    end

    local function remove_last_scalar(value)
        if value == "" then return value end
        local index = #value
        while index > 1 and value:byte(index) >= 0x80
            and value:byte(index) <= 0xBF
        do
            index = index - 1
        end
        return value:sub(1, index - 1)
    end

    local function append_raw(value, chunk, maximum_bytes)
        local current = value
        for index = 1, #chunk do
            local byte = chunk:byte(index)
            if byte == 0x08 or byte == 0x7F then
                current = remove_last_scalar(current)
            elseif byte < 0x20 then
                return nil, failure(
                    "InvalidSecretInput",
                    "Model Key input contains an unsupported control byte"
                )
            else
                if #current >= maximum_bytes then
                    return nil, failure("InputLimit", "Model setup input exceeds its byte limit")
                end
                current = current .. string.char(byte)
            end
        end
        return current
    end

    function input.read(prompt, secret, maximum_bytes)
        local mode = secret and "raw" or "cooked"
        local activated, activate_error = activate(mode)
        if not activated then return nil, activate_error end
        local written, write_error = output(prompt)
        if not written then return nil, write_error end
        local value = ""
        while true do
            local observed_now, clock_error = now()
            if not observed_now then return nil, clock_error end
            local called, events = pcall(active.poll, active, observed_now, 128)
            if not called or type(events) ~= "table" then
                return nil, failure(
                    "TerminalPollFailure",
                    "Model setup input polling failed"
                )
            end
            local progressed = false
            for _, event in ipairs(events) do
                progressed = true
                if event.kind == "io_terminal" then
                    terminal_ended = true
                    return false, { code = "ModelSetupCancelled" }
                end
                if event.kind ~= "user_action" then
                    return nil, failure(
                        "TerminalContract",
                        "Model setup received an invalid terminal event"
                    )
                end
                if event.action == "cancel" or event.action == "eof" then
                    return false, { code = "ModelSetupCancelled" }
                elseif event.action == "text" then
                    if type(event.text) ~= "string" then
                        return nil, failure(
                            "TerminalContract",
                            "Model setup text event is invalid"
                        )
                    end
                    if secret then
                        local appended, append_error = append_raw(
                            value,
                            event.text,
                            maximum_bytes
                        )
                        if not appended then return nil, append_error end
                        value = appended
                    else
                        if #value > maximum_bytes - #event.text then
                            return nil, failure(
                                "InputLimit",
                                "Model setup input exceeds its byte limit"
                            )
                        end
                        value = value .. event.text
                    end
                elseif event.action == "submit-or-queue" then
                    local valid, utf8_error = text.validate_utf8(value)
                    if not valid then
                        return nil, utf8_error or failure(
                            "InvalidInputEncoding",
                            "Model setup input is not valid UTF-8"
                        )
                    end
                    if secret then
                        written, write_error = output(value == "" and "[empty]\n" or "[hidden]\n")
                        if not written then return nil, write_error end
                    end
                    return value
                elseif event.action ~= "newline" then
                    return nil, failure(
                        "UnsupportedInputAction",
                        "Model setup accepts text, Enter, Esc, or EOF"
                    )
                end
            end
            if not progressed then
                local slept, sleep_error = pcall(
                    composed.backend.clock_port.sleep_ms,
                    10
                )
                if not slept or sleep_error == false then
                    return nil, failure(
                        "IdleWaitFailure",
                        "Model setup input wait failed"
                    )
                end
            end
        end
    end

    function input.write(bytes)
        return output(bytes)
    end

    function input.close()
        return close_active()
    end

    return input
end

local function default_model_name(generation)
    if type(generation) ~= "table" then return "Primary" end
    if type(generation.current_model) == "string" and generation.current_model ~= "" then
        return generation.current_model
    end
    if type(generation.model_order) == "table"
        and type(generation.model_order[1]) == "string"
    then
        return generation.model_order[1]
    end
    return "Primary"
end

local function another_enabled_model(generation, selected_name)
    if type(generation) ~= "table" or type(generation.models) ~= "table" then
        return false
    end
    for name, model in pairs(generation.models) do
        if name ~= selected_name and type(model) == "table" and model.enabled == true then
            return true
        end
    end
    return false
end

local function model_setup_cancelled(input)
    local written, write_error = input.write(
        "Model configuration cancelled; no configuration was changed.\n"
    )
    if not written then return nil, write_error end
    return readonly({
        outcome = "cancelled",
        action = "model-repl",
        state = "cancelled",
        online_requests = 0,
    }, "cancelled Model setup")
end

---Runs the offline first-Model/editor transaction with a raw no-echo Key field.
-- The flow never performs a connection test. Existing valid configurations are
-- edited through a stale-bound draft; only the exact yaca repair template may
-- enter the otherwise-forbidden invalid-source replacement path.
function M.run_model_repl(composed, runtime)
    if type(composed) ~= "table"
        or type(composed.config) ~= "table"
        or type(composed.config.begin_edit) ~= "function"
        or type(composed.config.begin_new_values) ~= "function"
        or type(composed.config.begin_exact_repair_values) ~= "function"
        or type(composed.backend) ~= "table"
        or type(composed.backend.new_terminal) ~= "function"
        or type(composed.backend.system) ~= "table"
        or type(composed.backend.system.secure_random) ~= "function"
        or type(runtime) ~= "table"
    then
        return nil, failure(
            "InvalidModelSetup",
            "Model setup requires the composed config and terminal services"
        )
    end
    local input = new_model_setup_input(composed, runtime)
    local function fail_input(original_error)
        local closed, close_error = input.close()
        if not closed then return nil, close_error end
        return nil, original_error
    end
    local function cancel_input()
        local result, result_error = model_setup_cancelled(input)
        local closed, close_error = input.close()
        if not result then return nil, result_error end
        if not closed then return nil, close_error end
        return result
    end
    local existing_draft, edit_error = composed.config.begin_edit(
        composed.layout.config_path
    )
    local mode, generation = "edit", nil
    if existing_draft then
        generation, edit_error = composed.config.draft_generation(existing_draft)
        if not generation then return fail_input(edit_error) end
    elseif type(edit_error) == "table" and edit_error.code == "NotFound" then
        mode = "create"
    else
        local existing = read_file_bytes(
            composed.backend.filesystem,
            composed.layout.config_path,
            #CONFIG_REPAIR_TEMPLATE
        )
        if existing == CONFIG_REPAIR_TEMPLATE then
            mode = "repair-template"
        else
            return fail_input(failure(
                "ConfigRepairRequired",
                "Model setup will not replace an arbitrary invalid configuration"
            ))
        end
    end

    local function read_value(prompt, secret)
        local value, value_error = input.read(prompt, secret, 16384)
        if value == false and type(value_error) == "table"
            and value_error.code == "ModelSetupCancelled"
        then
            return false
        end
        if value == nil then return nil, value_error end
        return value
    end

    local wrote, write_error = input.write(table.concat({
        "YACA MODEL SETUP\n",
        "Offline only: this publishes configuration and performs no network request.\n",
    }))
    if not wrote then return fail_input(write_error) end
    local suggested_name = default_model_name(generation)
    local name, read_error = read_value(
        "Model name [" .. model_setup_diagnostic(suggested_name, 128) .. "]: ",
        false
    )
    if name == false then return cancel_input() end
    if name == nil then return fail_input(read_error) end
    if name == "" then name = suggested_name end
    local current = generation and generation.models and generation.models[name] or nil

    local default_protocol = current and current.protocol or "openai-chat"
    local protocol
    while true do
        protocol, read_error = read_value(
            "Protocol [" .. default_protocol .. "] (openai-chat|anthropic-messages): ",
            false
        )
        if protocol == false then return cancel_input() end
        if protocol == nil then return fail_input(read_error) end
        if protocol == "" then protocol = default_protocol end
        if protocol == "openai-chat" or protocol == "anthropic-messages" then break end
        local shown, shown_error = input.write("Protocol must be openai-chat or anthropic-messages.\n")
        if not shown then return fail_input(shown_error) end
    end

    local default_enabled = current and current.enabled == false and "no" or "yes"
    local enabled
    while true do
        local enabled_text
        enabled_text, read_error = read_value(
            "Enable this Model? [" .. default_enabled .. "] (yes|no): ",
            false
        )
        if enabled_text == false then return cancel_input() end
        if enabled_text == nil then return fail_input(read_error) end
        enabled_text = enabled_text == "" and default_enabled or enabled_text:lower()
        if enabled_text ~= "yes" and enabled_text ~= "no" then
            local shown, shown_error = input.write("Enable answer must be yes or no.\n")
            if not shown then return fail_input(shown_error) end
        elseif enabled_text == "no" and not another_enabled_model(generation, name) then
            local shown, shown_error = input.write(
                "At least one Model must remain enabled; answer yes for this Model.\n"
            )
            if not shown then return fail_input(shown_error) end
        else
            enabled = enabled_text == "yes"
            break
        end
    end

    local default_endpoint = current and current.endpoint or ""
    local endpoint
    while true do
        local suffix = default_endpoint ~= "" and " [keep current]" or ""
        endpoint, read_error = read_value("Endpoint" .. suffix .. ": ", false)
        if endpoint == false then return cancel_input() end
        if endpoint == nil then return fail_input(read_error) end
        if endpoint == "" then endpoint = default_endpoint end
        if endpoint ~= "" or not enabled then break end
        local shown, shown_error = input.write("Endpoint is required for an enabled Model.\n")
        if not shown then return fail_input(shown_error) end
    end

    local default_remote = current and current.remote_model or ""
    local remote_model
    while true do
        local suffix = default_remote ~= "" and " [keep current]" or ""
        remote_model, read_error = read_value("Remote model" .. suffix .. ": ", false)
        if remote_model == false then return cancel_input() end
        if remote_model == nil then return fail_input(read_error) end
        if remote_model == "" then remote_model = default_remote end
        if remote_model ~= "" or not enabled then break end
        local shown, shown_error = input.write("Remote model is required for an enabled Model.\n")
        if not shown then return fail_input(shown_error) end
    end

    local key_prompt = current and current.key_configured == true
        and "Key (hidden; Enter keeps the configured value): "
        or "Key (hidden; Enter configures no key): "
    local key
    key, read_error = read_value(key_prompt, true)
    if key == false then return cancel_input() end
    if key == nil then return fail_input(read_error) end

    local summary = string.format(
        "Publish Model.%s protocol=%s endpoint=%s remote=%s enabled=%s key=%s\n",
        model_setup_diagnostic(name, 128),
        protocol,
        model_setup_diagnostic(endpoint, 1024),
        model_setup_diagnostic(remote_model, 256),
        tostring(enabled),
        key ~= "" and "provided" or (current and current.key_configured and "kept" or "none")
    )
    wrote, write_error = input.write(summary)
    if not wrote then return fail_input(write_error) end
    local confirmation
    confirmation, read_error = read_value(
        "Type APPLY to publish, or press Enter to cancel: ",
        false
    )
    if confirmation == false or confirmation == "" then
        return cancel_input()
    end
    if confirmation == nil then return fail_input(read_error) end
    if confirmation ~= "APPLY" then
        return cancel_input()
    end
    local closed, close_error = input.close()
    if not closed then return nil, close_error end

    local values = {
        name = name,
        protocol = protocol,
        endpoint = endpoint,
        remote_model = remote_model,
        key = key,
        enabled = enabled,
    }
    local draft, draft_error
    if mode == "edit" then
        draft, draft_error = composed.config.edit_draft(
            existing_draft,
            model_setup_changes(values)
        )
    else
        local sections = model_setup_sections(values)
        if mode == "create" then
            local created_root, root_error = ensure_data_root(
                composed.backend.filesystem,
                composed.layout.data_root,
                composed.layout.application_root
            )
            if created_root == nil then return nil, root_error end
            draft, draft_error = composed.config.begin_new_values(
                composed.layout.config_path,
                sections
            )
        else
            draft, draft_error = composed.config.begin_exact_repair_values(
                composed.layout.config_path,
                CONFIG_REPAIR_TEMPLATE,
                sections
            )
        end
    end
    key = nil
    if not draft then return nil, draft_error end
    local committed, commit_error
    for _ = 1, 8 do
        local random, random_error = composed.backend.system.secure_random(12)
        if not random then return nil, random_error end
        local temporary = composed.layout.config_path
            .. ".yaca-edit-" .. hex_bytes(random) .. ".tmp"
        committed, commit_error = composed.config.commit_draft(draft, temporary)
        if committed then break end
        local code = type(commit_error) == "table" and commit_error.code or nil
        if code ~= "DestinationExists" and code ~= "AlreadyExists"
            and code ~= "TemporaryConflict"
        then
            break
        end
    end
    if not committed then return nil, commit_error end
    if not write_direct(
        runtime.stdout,
        "Model " .. model_setup_diagnostic(name, 128)
            .. " was published offline. No network request was made.\n"
    ) then
        return nil, failure("BrokenStdout", "Model setup result could not be written")
    end
    return readonly({
        outcome = "success",
        action = "model-repl",
        state = "published",
        config_path = composed.layout.config_path,
        model_name = name,
        config_generation = committed.id,
        online_requests = 0,
    }, "published Model setup")
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
        return "Model configuration requires the interactive offline editor for "
            .. safe_diagnostic(result.config_path, 1024) .. ".\n"
    end
    if result.action == "context-repl" then
        if result.state == "scan-failed" then
            return "Context catalog scan failed ("
                .. safe_diagnostic(result.error_code, 128) .. ").\n"
        end
        local lines = {
            string.format(
                "CONTEXT CATALOG view=%s total=%d shown=%d sort=%s-%s",
                result.view,
                result.total,
                result.shown,
                result.sort_by,
                result.sort_direction
            ),
        }
        if result.shown == 0 then
            lines[#lines + 1] = "No Contexts found."
        else
            for index, row in ipairs(result.rows) do
                lines[#lines + 1] = string.format(
                    "%3d [%-11s] %s  %s  %s",
                    index,
                    row.header_state:upper(),
                    row.hash16,
                    safe_diagnostic(row.display_name, 256),
                    safe_diagnostic(row.logical_path, 1024)
                )
            end
        end
        if result.truncated then
            lines[#lines + 1] = string.format(
                "Page limited to %d rows; refresh or narrow the catalog view.",
                result.page_limit
            )
        end
        lines[#lines + 1] = string.format(
            "catalog complete=%s busy=%d corrupt=%d unavailable=%d changed=%d",
            tostring(result.state == "catalog-ready"),
            result.statistics.busy,
            result.statistics.corrupt,
            result.statistics.unavailable,
            result.statistics.changed
        )
        if result.state == "scan-incomplete" then
            lines[#lines + 1] = "Scan incomplete: "
                .. safe_diagnostic(result.partial_reason, 128)
        end
        lines[#lines + 1] = "Target qualification remains pending for release platforms."
        return table.concat(lines, "\n") .. "\n"
    end
    return "The requested management action is unavailable.\n"
end

local function render_runtime_result(cli_service, request, result)
    if request.id == "self-test" then return render_self_test(cli_service, request, result) end
    if BOOTSTRAP_ACTIONS[request.id] then return render_management(request, result) end
    return nil, failure(
        "InteractiveDispatchRequired",
        "run-chat must be owned by the terminal ApplicationCoordinator"
    )
end

default_runtime_dispatch = function(request, runtime)
    local composed, composition_error = M.compose_runtime(runtime)
    if not composed then return nil, composition_error end
    local result, dispatch_error = composed.application.dispatch(request)
    if not result then return nil, dispatch_error end
    if request.id == "model-repl" then
        local configured, setup_error = M.run_model_repl(composed, runtime)
        if not configured then return nil, setup_error end
        return {
            output = "",
            exit_value = configured.outcome == "success" and nil or configured,
        }
    end
    if request.id == "run-chat" or request.id == "continue" then
        local initial_agent
        if request.id == "continue" then
            initial_agent, dispatch_error = M.start_published_agent(
                composed,
                result,
                CONTINUATION_INSTRUCTION,
                "context-reopen"
            )
            if not initial_agent then
                local called, closed, close_error = pcall(result.draft.close)
                if not called or closed == nil then
                    return nil, close_error or failure(
                        "ContextLeaseUnknown",
                        "existing Context writer release is unknown"
                    )
                end
                return nil, dispatch_error
            end
        end
        local interactive, interactive_error = M.run_interactive_chat(
            composed,
            result,
            runtime,
            initial_agent
        )
        if not interactive then return nil, interactive_error end
        return { output = "" }
    end
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
