--[[
Author: WaterRun
Date: 2026-09-23
File: main.lua
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

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param next_action string|nil Suggested recovery action for the user-facing diagnostic.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, next_action)
    local result = { code = code, message = message }
    if next_action ~= nil then result.next_action = next_action end
    return result
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __len function Reports the backing table sequence length.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        -- Forward sequence-length queries to the backing table.
        --@param none The proxy operand supplied by Lua is ignored.
        --@return integer Length of the backing sequence under the Lua length operator.
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

---Copies a plain composition value into read-only proxies, rejecting cycles.
--@param value any Value to freeze recursively.
--@param visiting table|nil Ancestor set shared by recursive calls.
--@param label string|nil Proxy diagnostic label.
--@return any|nil frozen Read-only copy, or nil for cyclic tables.
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

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

---Checks a dense one-based array of nonempty NUL-free strings.
--@param values any Candidate argument or configuration array.
--@return boolean valid Whether every index and value is admissible.
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

---Copies finite plain data without cycles or executable Lua values.
--@param value any Candidate scalar or nested table.
--@param visiting table|nil Ancestor set for recursive calls.
--@return any|nil copied Detached plain value when valid.
--@return boolean valid Whether the complete value is plain and finite.
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

---Compares nested plain values for a stable configuration binding.
--@param left any First value.
--@param right any Second value.
--@param visited table|nil Previously compared table pairs.
--@return boolean equal Whether both structures have equal keys and values.
local function plain_equal(left, right, visited)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    visited = visited or {}
    if visited[left] == right then return true end
    visited[left] = right
    for key, value in pairs(left) do
        if not plain_equal(value, right[key], visited) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

---Checks a NUL-free absolute POSIX, drive, or UNC path.
--@param value any Candidate physical path.
--@return boolean valid Whether the path is absolute.
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

---Validates the observed executable path in the release target's path syntax.
--@param value any Native-observed executable path.
--@param style string Linux or Windows path style.
--@return string|nil path Canonical executable path or nil when ambiguous.
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

---Extracts the directory of a canonical native executable path.
--@param path string Canonical executable path.
--@param style string Linux or Windows path style.
--@return string|nil directory Parent directory when one exists.
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

---Joins a trusted root and one leaf using the release target separator.
--@param root string Canonical parent directory.
--@param leaf string Child path component.
--@param style string Linux or Windows path style.
--@return string path Joined physical path.
local function join_path(root, leaf, style)
    local separator = style == "windows" and "\\" or "/"
    if root:sub(-1) == separator then return root .. leaf end
    return root .. separator .. leaf
end

---Resolves durable and ephemeral roots from observed executable identities.
-- The outer onefile executable owns adjacent user data. The inner extracted
-- executable owns immutable bundled components; neither root is derived from
-- cwd, PATH text, or a caller-provided resource directory.
--@param native table Native port exposing executable_paths(argv0).
--@param argv0 string Original process argv[0] preserved by the onefile launcher.
--@param target_id string One exact release target id.
--@return table|nil Immutable runtime layout.
--@return table|nil Structured layout failure.
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

---Bounds diagnostic text and replaces control bytes before display.
--@param value any Candidate error message.
--@param maximum_bytes integer Maximum retained message bytes.
--@return string safe Sanitized bounded diagnostic text.
local function safe_diagnostic(value, maximum_bytes)
    value = type(value) == "string" and value or "internal failure"
    value = value:gsub("[%z\1-\31\127]", "?")
    if #value > maximum_bytes then value = value:sub(1, maximum_bytes) .. "..." end
    return value
end

---Escapes non-ASCII bytes for a portable terminal diagnostic.
--@param value any Candidate error message.
--@param maximum_bytes integer Maximum retained message bytes.
--@return string ascii ASCII-only diagnostic text.
local function ascii_diagnostic(value, maximum_bytes)
    return (safe_diagnostic(value, maximum_bytes):gsub(
        "[\128-\255]",
        ---Formats one non-ASCII byte as a hexadecimal escape.
        --@param byte string One matched byte.
        --@return string escaped ASCII hexadecimal byte escape.
        function(byte) return string.format("\\x%02X", byte:byte()) end
    ))
end

-- Shares the public Session fields between the one-shot CLI status and chat.
-- No selector lookup or storage scan belongs to this projection.
--@param status table Public Session status fields.
--@param render function|nil Diagnostic text renderer.
--@return table lines Ordered status lines for CLI or chat.
local function session_status_lines(status, render)
    render = render or safe_diagnostic
    local hash = status.context_hash
    if type(hash) ~= "string" or #hash ~= 16 or hash:find("[^0-9A-F]") then
        hash = "none"
    end
    if status.stale then hash = "stale" end
    local config_state = status.config_generation or "unavailable"
    if status.config_error then config_state = "unavailable (" .. status.config_error .. ")" end
    local double_check = "unavailable"
    if type(status.double_check) == "boolean" then
        double_check = tostring(status.double_check)
    end
    return {
        "workspace: " .. render(status.workspace or "unavailable", 1024),
        "context: " .. render(status.display_name or "new (not saved)", 256),
        "context hash: " .. hash,
        "config: " .. render(config_state, 192),
        "model: " .. render(status.model or "unavailable", 128),
        "permission: " .. render(status.permission or "unavailable", 128),
        "double-check: " .. double_check,
    }
end

---Writes one output chunk through a function or writer object safely.
--@param writer function|table Output writer.
--@param bytes string Chunk to write.
--@return boolean written Whether the writer accepted the complete call.
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

---Renders a stable ASCII error line without leaking control bytes.
--@param writer function|table Diagnostic output writer.
--@param err table|any Structured error or thrown value.
--@return boolean written Whether the diagnostic was written.
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

---Validates argv[0] and copies dense NUL-free process arguments.
--@param arguments table Process argv with index zero.
--@return table|nil invocation Detached argv0 and argument values.
--@return table|nil err Structured usage failure.
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

---Loads only the bundled native module from the fixed runtime path.
--@param none No arguments.
--@return table|nil native Opened native module.
--@return table|nil err Structured loader failure.
--@return string|nil path Absolute bundled native module path.
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

---Checks native ABI and maps the observed OS/architecture to a release target.
--@param native table Candidate bundled native module.
--@return table|nil identity Admitted OS, architecture, and target.
--@return table|nil err Structured ABI or platform failure.
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

---Builds the bounded CLI parser and machine-output codec for one platform.
--@param platform_name string Admitted release target ID.
--@return table|nil cli Bounded CLI service.
--@return table|nil err Structured codec or CLI construction failure.
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
--@param arguments table Process arguments including string argv[0].
--@param ports table|nil Test/runtime injection for native and output writers.
--@return integer Stable CLI exit code.
function M.run_cli(arguments, ports)
    ports = ports or {}
    local native, native_error, native_path
    ---Attempts native console output, leaving pipe fallback to the caller.
    --@param stream string Stdout or stderr target.
    --@param bytes string UI output bytes.
    --@return boolean|nil written True on console write, false on failure, nil for a pipe.
    local function write_console(stream, bytes)
        if not native or type(native.console_write) ~= "function" then return nil end
        local ok, result = native.console_write(stream, bytes)
        if ok then return true end
        if result and result.code == "NotConsole" then return nil end
        return false
    end
    ---Writes stdout with immediate flushing for Cygwin PTY visibility.
    --@param bytes string User-facing output chunk.
    --@return boolean written Whether native console or standard output accepted it.
    local stdout = ports.stdout or function(bytes)
        local console = write_console("stdout", bytes)
        if console ~= nil then return console end
        local result = io.stdout:write(bytes)
        -- A Cygwin PTY is a pipe to the Windows C runtime. Flush each UI write
        -- so prompts and streamed answers are visible before input is read.
        return result ~= nil and io.stdout:flush() ~= nil
    end
    ---Writes stderr through native console or the process error stream.
    --@param bytes string Diagnostic output chunk.
    --@return boolean written Whether the output stream accepted it.
    local stderr = ports.stderr or function(bytes)
        local console = write_console("stderr", bytes)
        if console ~= nil then return console end
        local result = io.stderr:write(bytes)
        return result ~= nil
    end
    local invocation, argument_error = copy_arguments(arguments)
    if not invocation then
        diagnostic(stderr, argument_error)
        return 2
    end

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

---Checks the narrow services admitted into the side-effect-free application root.
--@param components table Platform, Config, Workspace, and optional runtime services.
--@return table|nil components Admitted service record.
--@return table|nil err Structured missing or ambiguous component failure.
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

---Validates product identity, target, Config path, and draft limit.
--@param options table Candidate application construction options.
--@return table|nil options Admitted option record.
--@return table|nil err Structured option failure.
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

---Checks one semantic CLI action and its exact allowed fields.
--@param request table Parsed semantic action record.
--@return table|nil request Admitted original request.
--@return table|nil err Structured usage failure.
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
        status = { id = true },
        ["export-context"] = { id = true, selector = true },
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
    if request.id == "export-context" and request.selector ~= nil
        and (type(request.selector) ~= "string" or request.selector == "")
    then
        return nil, failure("UsageError", "export requires a valid Context selector")
    end
    return request
end

---Maps low-level Config read failures to stable user-facing recovery guidance.
--@param config_error table|nil Config service failure.
--@return table err Normalized ConfigMissing or ConfigInvalid diagnostic.
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

---Private continuation credentials survive only an exact in-process handoff.
--@metatable continuation_previews Associates continuation previews with the workspace and Context facts requiring confirmation.
--@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
local continuation_previews = setmetatable({}, { __mode = "k" })

---Creates the side-effect-free application composition root.
-- No component method is called until dispatch receives an explicit semantic
-- action. Bootstrap-safe routes never receive the optional network/agent ports.
--@param components table Injected platform/config/workspace/offline handlers.
--@param options table Product identity, config path, target, and draft cap.
--@return table|nil application Immutable application facade.
--@return table|nil err Structured construction failure.
function M.new(components, options)
    local admitted_components, components_error = validate_components(components)
    if not admitted_components then return nil, components_error end
    local admitted, options_error = validate_options(options)
    if not admitted then return nil, options_error end

    local platform_attempted = false
    local platform_identity
    local platform_error
    local active_draft
    local latest_continue_preview
    local lifecycle = "constructed"
    local application = {}

    ---Checks release target identity exactly once for this application.
    --@param none No arguments.
    --@return table|nil identity Admitted platform identity.
    --@return table|nil err Structured platform failure.
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

    ---Loads the current ConfigGeneration with optional Context overrides.
    --@param overrides table|nil Durable Session override values.
    --@return table|nil generation Validated ConfigGeneration.
    --@return table|nil err Normalized Config failure.
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

    ---Freezes product, platform, Config, and enabled Model self-test facts.
    --@param identity table Admitted platform identity.
    --@param generation table|nil Current ConfigGeneration.
    --@param config_error table|nil Config load failure.
    --@return table|nil projection Immutable self-test snapshot and Model list.
    --@return table|nil err Structured snapshot failure.
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

    ---Runs one explicit offline or consented-online self-test specification.
    --@param mode string Requested self-test mode.
    --@param request table Parsed self-test filters and stage.
    --@param identity table Admitted platform identity.
    --@param generation table|nil Current ConfigGeneration.
    --@param config_error table|nil Config load failure.
    --@return table|nil report Immutable self-test report.
    --@return table|nil err Structured snapshot or runner failure.
    local function run_self_test(mode, request, identity, generation, config_error)
        local projection, projection_error = self_test_snapshot(
            identity,
            generation,
            config_error
        )
        if not projection then return nil, projection_error end
        local excluded_models = {}
        for index, selector in ipairs(request.excluded_models or {}) do
            excluded_models[index] = generation
                and require("config").resolve_resource(generation, "Model", selector) or selector
            if not excluded_models[index] then excluded_models[index] = selector end
        end
        local specification = freeze({
            mode = mode,
            through_stage = request.through_stage or 1,
            list_checks = request.list_checks == true,
            online_consent = request.online_consent == true,
            excluded_models = excluded_models,
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

    ---Routes an explicit self-test action with its selected stage and consent.
    --@param request table Parsed self-test action.
    --@return table|nil report Self-test result for rendering.
    --@return table|nil err Structured platform, Config, or runner failure.
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

    ---Runs an offline bootstrap management action.
    --@param request table Parsed Config, Model, or Context management action.
    --@return table|nil result Management result for rendering.
    --@return table|nil err Structured management failure.
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

    ---Projects current public application status without opening Agent effects.
    --@param none No arguments.
    --@return table|nil status Public Session and platform state.
    --@return table|nil err Structured platform or Config failure.
    local function dispatch_status()
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local generation, config_error
        local current
        if active_draft then
            current = active_draft.status()
            generation = active_draft.config_generation()
        else
            generation, config_error = load_config()
            local called, workspace = pcall(admitted_components.workspace.inspect, ".")
            current = {
                workspace = called and type(workspace) == "table"
                    and workspace.path or false,
                durable = false,
                display_name = "none",
                context_hash = false,
            }
        end
        local double_check
        if active_draft then
            double_check = current.double_check
        elseif generation then
            double_check = generation.effective_double_check
        end
        return readonly({
            kind = "status",
            outcome = "success",
            product = admitted.product_name,
            version = admitted.product_version,
            release_target = admitted.release_target,
            state = active_draft and current.lifecycle or "no-active-context",
            workspace = current.workspace,
            durable = current.durable == true,
            display_name = current.display_name or "not saved",
            context_hash = current.context_hash or false,
            config_available = generation ~= nil,
            config_generation = generation and generation.id or false,
            config_error = config_error and config_error.code or false,
            model = current.model or (generation and generation.current_model) or false,
            permission = current.permission
                or (generation and generation.current_permission) or false,
            double_check = double_check,
            agent_ready = generation and generation.agent_ready == true or false,
        }, "read-only invocation status")
    end

    ---Requires the bounded startup checks for an Agent-ready ConfigGeneration.
    --@param generation table Current ConfigGeneration.
    --@return boolean|nil ready True when startup checks pass.
    --@return table|nil err Structured readiness failure.
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

    ---Creates one fresh chat draft from the current Workspace and Config.
    --@param request table Parsed run-chat action.
    --@return table|nil draft Active draft Session facade.
    --@return table|nil err Structured Workspace, Config, or readiness failure.
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

    ---Calls a Context port while normalizing raised exceptions to one diagnostic.
    --@param callable function Context service operation.
    --@param code string Failure code for an exception or missing result.
    --@param message string Failure summary for the caller.
    --@param ... any Context port arguments.
    --@return any|nil result Port result on success.
    --@return table|nil err Structured port failure.
    local function context_call(callable, code, message, ...)
        local called, value, value_error = pcall(callable, ...)
        if not called then return nil, failure(code, message .. " raised an exception") end
        if value == nil then return nil, value_error or failure(code, message .. " failed") end
        return value, value_error
    end

    ---Maps a non-unique Context selector result to a stable diagnostic.
    --@param selection table Resolver result with ambiguity or missing tag.
    --@return table err Structured Context selection failure.
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

    ---Exports a selected Context through read-only, identity-bound validation.
    --@param request table Parsed export action and optional selector.
    --@return table|nil result Markdown export and Context identity.
    --@return table|nil err Structured selection, secret, or target failure.
    local function dispatch_export(request)
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        if request.selector == nil and (not active_draft or not active_draft.status().durable) then
            return nil, failure(
                "NoActiveContext",
                "no Context is open in this process; provide an exact name or hash"
            )
        end
        local generation = load_config()
        if not generation and active_draft then generation = active_draft.config_generation() end
        local scan = generation and generation.scan_registered_secrets or nil
        local markdown, receipt
        if request.selector == nil then
            local publication = admitted_components.publication
            if not publication or type(publication.export_active) ~= "function" then
                return nil, failure("ContextUnavailable", "active Context export is unavailable")
            end
            markdown, receipt = context_call(
                publication.export_active, "ContextExportFailure", "active Context export", scan
            )
            if not markdown then return nil, receipt end
        else
            local catalog = admitted_components.context_catalog
            if not catalog or type(catalog.store) ~= "table"
                or type(catalog.store.inspect_import) ~= "function"
                or type(catalog.schema) ~= "table" or type(catalog.schema.export) ~= "function"
            then
                return nil, failure("ContextUnavailable", "read-only Context export is unavailable")
            end
            local workspace, workspace_error = context_call(
                admitted_components.workspace.inspect,
                "InvalidWorkspace", "current workspace inspection", "."
            )
            if not workspace then return nil, workspace_error end
            local origin, origin_error = context_call(
                catalog.path.to_logical, "UnsupportedPath", "current workspace conversion", workspace.path
            )
            if not origin then return nil, origin_error end
            local selection, selection_error = context_call(
                catalog.resolver.resolve, "ContextSelectionFailure", "Context selection",
                request.selector, origin
            )
            if not selection then return nil, selection_error end
            if selection.tag ~= "Unique" then return nil, context_selection_error(selection) end
            local verified, verify_error = context_call(
                catalog.resolver.verify_target, "ContextTargetVerificationFailure",
                "Context export target verification", selection, "open"
            )
            if not verified then return nil, verify_error end
            if verified.tag ~= "Verified" then
                return nil, failure(
                    verified.tag == "TargetChanged" and "TargetChanged" or "MatchedUnavailable",
                    "the selected Context is unavailable for export"
                )
            end
            if type(verified.logical_path) ~= "string"
                or type(verified.physical_hint) ~= "string"
                or type(verified.hash) ~= "string" or #verified.hash ~= 16
                or verified.hash:find("[^0-9A-F]")
                or type(verified.credential) ~= "table"
            then
                return nil, failure("ContextTargetVerificationFailure", "Context export target is incomplete")
            end
            local document, read_error = context_call(
                catalog.store.inspect_import, "ContextExportFailure", "read-only Context validation",
                verified.physical_hint, verified.credential
            )
            if not document then return nil, read_error end
            markdown, read_error = context_call(
                catalog.schema.export, "ContextExportFailure", "Context Markdown export", document, nil, scan
            )
            if not markdown then return nil, read_error end
            local current, current_error = context_call(
                catalog.resolver.verify_target, "ContextTargetVerificationFailure",
                "Context export final verification", selection, "open"
            )
            if not current then return nil, current_error end
            if current.tag ~= "Verified" or current.logical_path ~= verified.logical_path
                or current.hash ~= verified.hash or current.physical_hint ~= verified.physical_hint
                or not plain_equal(current.credential, verified.credential)
            then
                return nil, failure("TargetChanged", "the selected Context changed before export completed")
            end
            receipt = {
                context_hash = verified.hash, logical_path = verified.logical_path,
                generation = document.generation,
            }
        end
        if type(markdown) ~= "string" or type(receipt) ~= "table" then
            return nil, failure("ContextExportFailure", "Context export returned an invalid result")
        end
        return readonly({
            kind = "context-export", outcome = "success", format = "markdown",
            markdown = markdown, context_hash = receipt.context_hash,
            logical_path = receipt.logical_path, generation = receipt.generation,
        }, "read-only Context export result")
    end

    ---Compares the stable object identity of two observed workspaces.
    --@param left table First workspace file identity.
    --@param right table Second workspace file identity.
    --@return boolean equal Whether kind, volume, and object match.
    local function workspace_identity_equal(left, right)
        return type(left) == "table"
            and type(right) == "table"
            and left.kind == right.kind
            and left.volume == right.volume
            and left.object == right.object
    end

    ---Previews or opens one existing Context under exact target and Workspace binding.
    --@param request table Parsed continuation selector.
    --@param preview_only boolean Whether to stop before opening the writer.
    --@param bound_preview table|nil Previously confirmed private preview facts.
    --@return table|nil result Preview or active continued Session draft.
    --@return table|nil err Structured stale, recovery, or configuration failure.
    local function dispatch_continue(request, preview_only, bound_preview)
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
        local origin_path = "."
        if bound_preview then
            origin_path = bound_preview.origin.path
        elseif active_draft then
            origin_path = active_draft.status().workspace
        end
        local inspected, workspace, workspace_error = pcall(
            admitted_components.workspace.inspect, origin_path
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
        if bound_preview and (verified.logical_path ~= bound_preview.verified.logical_path
            or verified.hash ~= bound_preview.verified.hash
            or verified.physical_hint ~= bound_preview.verified.physical_hint
            or not plain_equal(verified.credential, bound_preview.verified.credential)
            or workspace.path ~= bound_preview.origin.path
            or not workspace_identity_equal(workspace.identity, bound_preview.origin.identity))
        then
            return nil, failure("TargetChanged", "the confirmed Context or origin workspace changed")
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
        local cross_workspace = origin_key ~= expected_key
            or not workspace_identity_equal(workspace.identity, recorded_workspace.identity)
        if bound_preview and (recorded_workspace.path ~= bound_preview.recorded.path
            or not workspace_identity_equal(recorded_workspace.identity, bound_preview.recorded.identity))
        then
            return nil, failure("TargetChanged", "the confirmed Context workspace changed")
        end
        ---Rechecks both origin and recorded Workspace objects before handoff.
        --@param none No arguments.
        --@return boolean|nil valid True while both identities remain exact.
        --@return table|nil err Structured changed-workspace failure.
        local function reverify_workspaces()
            for _, expected in ipairs({ workspace, recorded_workspace }) do
                local current, current_error = context_call(admitted_components.workspace.inspect,
                    "InvalidWorkspace", "continuation workspace reverification", expected.path)
                if not current then return nil, current_error end
                if current.path ~= expected.path
                    or not workspace_identity_equal(current.identity, expected.identity)
                then
                    return nil, failure("TargetChanged", "continuation workspace identity changed")
                end
            end
            return true
        end
        local workspace_valid, workspace_verify_error = reverify_workspaces()
        if not workspace_valid then return nil, workspace_verify_error end
        if preview_only then
            verified = assert(freeze(verified, {}, "continuation target"))
            workspace = assert(freeze(workspace, {}, "continuation origin"))
            recorded_workspace = assert(freeze(recorded_workspace, {}, "continuation workspace"))
            local preview = readonly({
                kind = "continue-preview",
                selector = request.selector,
                logical_path = verified.logical_path,
                context_hash = verified.hash,
                origin_workspace = workspace.path,
                recorded_workspace = recorded_workspace.path,
                requires_workspace_confirmation = cross_workspace,
            }, "existing Context continuation preview")
            if latest_continue_preview then continuation_previews[latest_continue_preview] = nil end
            latest_continue_preview = preview
            continuation_previews[preview] = {
                verified = verified, origin = workspace, recorded = recorded_workspace,
                config_path = admitted.config_path,
                ---Revalidates the preview target and both Workspace identities.
                --@param none No arguments.
                --@return boolean|nil valid True while preview facts remain current.
                --@return table|nil err Structured stale-preview failure.
                verify = function()
                    if lifecycle == "closed" then
                        return nil, failure("InvalidContinuePreview", "continuation preview owner is closed")
                    end
                    local current, current_error = context_call(catalog.resolver.verify_target,
                        "ContextTargetVerificationFailure", "confirmed Context reverification", selection, "open")
                    if not current then return nil, current_error end
                    if current.tag ~= "Verified" or not plain_equal(current.credential, verified.credential)
                        or current.hash ~= verified.hash or current.logical_path ~= verified.logical_path
                        or current.physical_hint ~= verified.physical_hint
                    then
                        return nil, failure("TargetChanged", "the previewed Context changed before continuation")
                    end
                    return reverify_workspaces()
                end,
            }
            return preview
        end
        if cross_workspace and not bound_preview then
            return nil, failure("WorkspaceConfirmationRequired",
                "the selected Context belongs to another workspace; run continue from " .. recorded_path,
                "Run --continue from the recorded workspace: " .. recorded_path)
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
        ---Closes a newly opened writer before returning a continuation failure.
        --@param primary_error table Original structured continuation failure.
        --@return nil No draft is returned after opening fails.
        --@return table err Original failure or unknown-lease failure.
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
        workspace_valid, workspace_verify_error = reverify_workspaces()
        if not workspace_valid then return release_opened(workspace_verify_error) end
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

        workspace_valid, workspace_verify_error = reverify_workspaces()
        if not workspace_valid then return release_opened(workspace_verify_error) end

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
        ---Returns the immutable status of this opened Context Session.
        --@param none No arguments.
        --@return table status Public opened Session status.
        function draft.status() return status end
        ---Returns the ConfigGeneration used by this continued Session.
        --@param none No arguments.
        --@return table generation Current validated ConfigGeneration.
        function draft.config_generation() return generation end
        ---Returns the durable Context-open receipt for runtime handoff.
        --@param none No arguments.
        --@return table receipt Exact Context-open receipt.
        function draft.open_receipt() return receipt end
        ---Closes the owned Context writer once and retains release failures.
        --@param none No arguments.
        --@return boolean|nil closed True on release, false if already closed.
        --@return table|nil err Structured unknown-lease failure.
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
            workspace_identity = assert(freeze(
                recorded_workspace.identity, {}, "continued workspace identity"
            )),
        }, "existing chat bootstrap result")
    end


    ---Resolves and reverifies one continuation target without acquiring its
    -- writer. This is the first phase of an in-chat Context switch; the later
    -- open must use the returned precise hash and repeat all verification.
    --@param selector string User-selected Context name or hash.
    --@return table|nil preview Read-only target and Workspace binding.
    --@return table|nil err Structured selection or verification failure.
    function application.preview_continue(selector)
        if lifecycle == "closed" then
            return nil, failure("ApplicationClosed", "the application lifecycle is closed")
        end
        if type(selector) ~= "string" or selector == "" then
            return nil, failure("UsageError", "continue preview requires one Context selector")
        end
        return dispatch_continue({ id = "continue", selector = selector }, true)
    end

    ---Consumes a private exact preview in this or a fresh composition. Cross-
    -- workspace admission requires the literal response supplied by the UI;
    -- all files and directories are reverified before acquiring a writer.
    --@param preview table Preview issued by this application or a fresh peer.
    --@param confirmation string|nil Literal cross-Workspace confirmation.
    --@return table|nil result Continued Context Session draft.
    --@return table|nil err Structured stale or confirmation failure.
    function application.continue_preview(preview, confirmation)
        if lifecycle == "closed" then return nil, failure("ApplicationClosed", "application is closed") end
        local plan = continuation_previews[preview]
        if not plan or plan.config_path ~= admitted.config_path then
            return nil, failure("InvalidContinuePreview", "continuation preview is stale or foreign")
        end
        if preview.requires_workspace_confirmation
            and confirmation ~= "CONTINUE " .. preview.context_hash
        then
            return nil, failure("WorkspaceConfirmationRequired", "the recorded workspace requires confirmation")
        end
        continuation_previews[preview] = nil
        local valid, verify_error = plan.verify()
        if not valid then return nil, verify_error end
        return dispatch_continue({ id = "continue", selector = preview.context_hash }, false, plan)
    end

    ---Dispatches one already-normalized semantic action.
    -- Parsing argv and rendering human/machine output are later adapters.
    --@param request table Parsed semantic CLI action.
    --@return table|nil result Bootstrap, management, or chat result.
    --@return table|nil err Structured action or lifecycle failure.
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
        if request.id == "status" then return dispatch_status() end
        if request.id == "export-context" then return dispatch_export(request) end
        if BOOTSTRAP_ACTIONS[request.id] then return dispatch_management(request) end
        if request.id == "continue" then return dispatch_continue(request) end
        return dispatch_chat(request)
    end

    ---Returns lifecycle facts without loading config or scanning Contexts.
    --@param none No arguments.
    --@return table status Immutable application lifecycle snapshot.
    function application.status()
        return readonly({
            lifecycle = lifecycle,
            active_draft = active_draft and active_draft.status() or false,
            platform_checked = platform_attempted,
        }, "application status")
    end

    ---Closes the current in-memory draft and prevents further dispatch.
    --@param none No arguments.
    --@return boolean|nil closed True after close, false if already closed.
    --@return table|nil err Structured draft release failure.
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
    maximum_tool_calls = 8,
    maximum_tool_argument_bytes = 32768,
    maximum_total_tool_argument_bytes = 262144,
    maximum_content_blocks = 256,
    maximum_events = 16384,
}

local MODEL_ACTIVITY_OPTIONS = {
    maximum_poll_events = 128,
    maximum_queued_events = 16386,
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
            message_bytes = 65536,
            result_bytes = 262144,
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
            ask = 0,
        },
        automatic_compaction = true,
        maximum_identifier_bytes = 256,
        hard_cap_snapshot_id = "tp017-modern-candidate-v1",
        lanes = {
            queue_maximum = 9,
            ask_active_time_ms = 120000,
            ask_response_bytes = 65536,
            ask_snapshot_id = "tp022-modern-candidate-v1",
        },
    },
}

local CONTINUATION_INSTRUCTION = table.concat({
    "Continue from the latest durable Context facts.",
    " Treat those facts as the canonical conversation and tool history.",
    " Use a typed control when the current turn has a reportable outcome.",
})

---Exposes the native monotonic clock to the production AgentLoop.
--@param backend table Admitted native backend with clock port.
--@return table clock Read-only Agent clock facade.
local function production_clock(backend)
    return readonly({
        now = backend.clock_port.monotonic_now,
    }, "production Agent clock")
end

---Projects configured Permission switches into the runtime permission names.
--@param configured table|nil Selected ConfigGeneration Permission.
--@return table|nil matrix Runtime Read/Write/Delete/Shell/OutsideWorkspace matrix.
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

---Serializes one observed Workspace object identity for Tool authority binding.
--@param identity table Native directory identity.
--@return string|nil key Volume, object, and kind composite.
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

---Builds a Tool authority port bound to this turn's immutable security facts.
--@param safety_service table Binding digest service.
--@param expected table Permission, Config, Workspace, and review expectations.
--@return table authorization Read-only admit/reverify port.
local function tool_authorization_port(safety_service, expected)
    ---Hashes one Tool call together with the exact admitted authority facts.
    --@param call table Candidate Tool call and call digest.
    --@param facts table Current permission, approval, intent, and review facts.
    --@return string|nil digest Exact authority digest or nil for a mismatch.
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
        ---Admits one Tool call only when its authority facts match this turn.
        --@param call table Candidate Tool call.
        --@param facts table Current authority evidence.
        --@return boolean admitted Whether the evidence matches.
        --@return string|nil digest Bound authority digest on success.
        admit = function(call, facts)
            local digest = authority_digest(call, facts)
            if not digest then return false end
            return true, digest
        end,
        ---Rechecks authority immediately before the Tool effect.
        --@param call table Candidate Tool call.
        --@param facts table Current authority evidence.
        --@param digest string Previously admitted authority digest.
        --@return boolean current Whether the exact authority still holds.
        reverify = function(call, facts, digest)
            local current = authority_digest(call, facts)
            return current ~= nil and current == digest
        end,
    }, "production Tool authorization")
end

---Derives bounded Tool limits from the selected ConfigGeneration and target.
--@param composed table Production runtime composition.
--@param generation table Selected ConfigGeneration.
--@param workspace_path string Native Workspace path.
--@return table options Direct Tool and execution hard limits.
local function tool_options(composed, generation, workspace_path)
    local output_limit = math.min((generation.exec.max_output_kb or 1024) * 1024,
        AGENT_RELEASE_OPTIONS.runtime.hard_caps.result_bytes // 4)
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
        -- Use the running inner payload: XP/Win7 cannot nest the outer
        -- extractor's Job inside the foreground tool's containment Job.
        lua_executable = composed.layout.runtime_executable,
        reserved_paths = { composed.layout.data_root },
    }
end

---Copies release AgentLoop caps so each owner gets independent mutable options.
--@param none No arguments.
--@return table|nil options Detached AgentLoop release options.
local function runtime_options()
    local candidate = copy_plain(AGENT_RELEASE_OPTIONS.runtime, {})
    if not candidate then return nil end
    return candidate
end

---Scopes Model activity IDs and response caps to one durable Context.
--@param composed table Production runtime composition.
--@param context_hash string Exact uppercase Context hash.
--@param ask boolean Whether to apply the smaller no-tool Ask caps.
--@return table|nil options Read-only scoped Model activity limits.
--@return table|nil err Structured identity or option failure.
local function scoped_model_activity_options(composed, context_hash, ask)
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
    if ask then
        candidate.maximum_turn_time_ms = math.min(
            candidate.maximum_turn_time_ms,
            AGENT_RELEASE_OPTIONS.runtime.lanes.ask_active_time_ms
        )
        candidate.maximum_canonical_body_bytes = math.min(
            candidate.maximum_canonical_body_bytes,
            AGENT_RELEASE_OPTIONS.runtime.lanes.ask_response_bytes
        )
    end
    return readonly(candidate, "Context-scoped Model activity options")
end

---Builds one generation-bound Model, Tool, review, and compaction port set.
--@param composed table Production runtime composition.
--@param shared table Durable journal, codec, clock, and Workspace binding.
--@param turn table Frozen turn selection and Context identity.
--@return table|nil ports Current turn activity ports and compaction binding.
--@return table|nil err Structured permission, identity, or port failure.
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
    if shared.workspace_identity and workspace_key ~= shared.workspace_identity then
        return nil, failure("ContextTargetChanged", "the confirmed workspace was replaced")
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
    local admitted_tool_options = tool_options(composed, generation, turn.workspace)
    local tool_service, tool_error = tools_module.new({
        filesystem = composed.backend.filesystem,
        path = contexts.path,
        safety = contexts.safety,
        secret_registry = secret_registry,
        authorization = authorization,
        processes = composed.backend.processes,
        operations = shared.operations,
    }, admitted_tool_options)
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
            output_limit_bytes = admitted_tool_options.maximum_exec_output_bytes,
            deadline_ms = admitted_tool_options.maximum_exec_deadline_ms,
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

---Builds an isolated no-tool Ask Model activity for one frozen Ask snapshot.
--@param composed table Production runtime composition.
--@param ask table Frozen Ask Model selection and Context identity.
--@return table|nil activity Ask generation and Model activity.
--@return table|nil err Structured builder or transport failure.
local function build_ask_activity(composed, ask)
    local model_module = require("model")
    local views = readonly({
        resolve_view = composed.publication.resolve_view,
    }, "durable ask Model views")
    local request_builder, builder_error = model_module.new_ask_request_builder({
        adapter = composed.model_adapter,
        prompt = composed.contexts.prompt,
        views = views,
        generation = ask.generation,
        tool_registry = composed.contexts.tool_registry,
        safety = composed.contexts.safety,
    }, {
        model_name = ask.model,
        permission_name = ask.permission,
        model_snapshot = ask.model_snapshot,
        permission_snapshot = ask.permission_snapshot,
        prompt_snapshot = ask.prompt_snapshot,
        tool_registry_snapshot = ask.tool_registry_snapshot,
        initial_message = ask.initial_message,
        context_prompt = ask.context_prompt,
        default_connect_timeout_ms = 120000,
        maximum_request_time_ms = AGENT_RELEASE_OPTIONS.runtime.lanes.ask_active_time_ms,
        default_retry_base_delay_ms = 1000,
        maximum_output_tokens = 1024,
    })
    if not request_builder then return nil, builder_error end
    local activity_options, activity_options_error = scoped_model_activity_options(
        composed,
        ask.context_hash,
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
        generation = ask.generation,
        view_manifest_ref = ask.view_manifest_ref,
        activity = activity,
    }
end

local ASK_RUNTIME_REQUEST_FIELDS = {
    ask_id = true,
    turn_id = true,
    request_id = true,
    purpose = true,
    view_manifest_ref = true,
    no_tools = true,
    active_time_cap_ms = true,
    response_byte_cap = true,
    budget_snapshot_id = true,
}

---Owns the prepared and active no-tool Ask Model activity independently.
--@param none No arguments.
--@return table catalog Read-only Ask activity catalog.
local function new_ask_catalog()
    local prepared = false
    local current = false
    local catalog = {}

    ---Checks whether an Ask activity has no active Model request.
    --@param candidate table|false Prepared or current Ask activity.
    --@return boolean idle Whether the activity is absent or idle.
    local function idle_activity(candidate)
        if not candidate then return true end
        local called, status = pcall(candidate.activity.status)
        return called and type(status) == "table" and status.state == "idle"
    end

    ---Checks both prepared and current Ask activity for idle state.
    --@param none No arguments.
    --@return boolean idle Whether Ask has no active Model effect.
    function catalog.idle()
        return idle_activity(prepared) and idle_activity(current)
    end

    ---Stages one generation-bound Ask activity while the lane is idle.
    --@param candidate table Ask generation, view, and activity port.
    --@return boolean|nil prepared True after staging.
    --@return table|nil err Structured busy or invalid-port failure.
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
                "InvalidAskActivity",
                "prepared ask Model activity is incomplete"
            )
        end
        if not catalog.idle() then
            return nil, failure(
                "AskActivityBusy",
                "a ask Model activity is already active"
            )
        end
        prepared = candidate
        return true
    end

    ---Starts a staged Ask request only for its exact frozen release snapshot.
    --@param specification table AgentLoop no-tool Ask request.
    --@return any|nil handle Active Model activity handle.
    --@return table|nil err Structured unavailable or binding failure.
    function catalog.start(specification)
        if type(specification) ~= "table" or not prepared then
            return nil, failure(
                "AskActivityUnavailable",
                "the frozen ask Model activity is unavailable"
            )
        end
        for key in pairs(specification) do
            if type(key) ~= "string" or not ASK_RUNTIME_REQUEST_FIELDS[key] then
                return nil, failure(
                    "InvalidAskActivity",
                    "ask Runtime request is ambiguous"
                )
            end
        end
        for key in pairs(ASK_RUNTIME_REQUEST_FIELDS) do
            if specification[key] == nil then
                return nil, failure(
                    "InvalidAskActivity",
                    "ask Runtime request is incomplete"
                )
            end
        end
        if specification.purpose ~= "ask"
            or specification.no_tools ~= true
            or specification.ask_id ~= specification.turn_id
            or specification.view_manifest_ref ~= prepared.view_manifest_ref
            or specification.active_time_cap_ms
                ~= AGENT_RELEASE_OPTIONS.runtime.lanes.ask_active_time_ms
            or specification.response_byte_cap
                ~= AGENT_RELEASE_OPTIONS.runtime.lanes.ask_response_bytes
            or specification.budget_snapshot_id
                ~= AGENT_RELEASE_OPTIONS.runtime.lanes.ask_snapshot_id
        then
            return nil, failure(
                "InvalidAskActivity",
                "ask Runtime request contradicts its frozen release snapshot"
            )
        end
        local handle, start_error = prepared.activity.start({
            request_id = specification.request_id,
            turn_id = specification.turn_id,
            purpose = "ask",
            continuation = false,
            view_manifest_ref = specification.view_manifest_ref,
            progress_identity = "ask:" .. specification.ask_id,
        })
        if not handle then return nil, start_error end
        current = prepared
        prepared = false
        return handle
    end

    ---Cancels the currently active Ask Model request.
    --@param handle any Active Ask activity handle.
    --@param reason string Cancellation reason.
    --@return table outcome Cancel result, unknown if no activity remains.
    function catalog.cancel(handle, reason)
        if not current then return { outcome = "unknown" } end
        return current.activity.cancel(handle, reason)
    end

    ---Polls a bounded batch from the active Ask Model activity.
    --@param budget integer Maximum activity events.
    --@return table events Ask events, empty when idle.
    --@return table|nil err Structured activity failure.
    function catalog.poll(budget)
        if not current then return {} end
        return current.activity.poll(budget)
    end

    ---Projects current Ask activity, prepared generation, or idle state.
    --@param none No arguments.
    --@return table status Ask activity status.
    function catalog.status()
        if current then return current.activity.status() end
        if prepared then return readonly({
            state = "prepared",
            generation = prepared.generation.id,
        }, "prepared ask activity status") end
        return readonly({ state = "idle" }, "ask activity status")
    end

    ---Returns the ConfigGeneration bound to prepared or active Ask work.
    --@param none No arguments.
    --@return table|false generation Bound ConfigGeneration or false when idle.
    function catalog.generation()
        local candidate = prepared or current
        return candidate and candidate.generation or false
    end

    return readonly(catalog, "production ask activity catalog")
end

---Provides stable Model, Tool, review, and compaction facades across turns.
--@param initial table Initial generation-bound activity ports.
--@return table catalog Read-only replaceable turn activity catalog.
local function new_turn_catalog(initial)
    local current = initial
    ---Forwards one activity call to the currently selected turn generation.
    --@param domain string Model, tools, reviews, or compaction port.
    --@param method string Port method name.
    --@param ... any Forwarded method arguments.
    --@return any result Current generation's method result.
    local function invoke(domain, method, ...)
        return current[domain][method](...)
    end
    local model = readonly({
        ---Starts a request on the currently bound Model activity.
        --@param ... any Model start arguments.
        --@return any result Current Model start result.
        start = function(...) return invoke("model", "start", ...) end,
        ---Cancels the currently bound Model activity.
        --@param ... any Model cancel arguments.
        --@return any result Current Model cancel result.
        cancel = function(...) return invoke("model", "cancel", ...) end,
        ---Polls the currently bound Model activity.
        --@param ... any Model poll arguments.
        --@return any result Current Model poll result.
        poll = function(...) return invoke("model", "poll", ...) end,
        ---Reads the currently bound Model activity status.
        --@param ... any Model status arguments.
        --@return any result Current Model status result.
        status = function(...) return invoke("model", "status", ...) end,
    }, "generation-bound Model port")
    local tools = readonly({
        ---Admits a Tool call through the current generation's policy port.
        --@param ... any Tool admission arguments.
        --@return any result Current Tool admission result.
        admit = function(...) return invoke("tools", "admit", ...) end,
        ---Starts an admitted Tool on the current generation.
        --@param ... any Tool start arguments.
        --@return any result Current Tool start result.
        start = function(...) return invoke("tools", "start", ...) end,
        ---Cancels a current-generation Tool activity.
        --@param ... any Tool cancel arguments.
        --@return any result Current Tool cancel result.
        cancel = function(...) return invoke("tools", "cancel", ...) end,
        ---Polls bounded Tool events from the current generation.
        --@param ... any Tool poll arguments.
        --@return any result Current Tool poll result.
        poll = function(...) return invoke("tools", "poll", ...) end,
        ---Prepares one exact approval for the current Tool call.
        --@param ... any Approval preparation arguments.
        --@return any result Current approval preparation result.
        prepare_approval = function(...)
            return invoke("tools", "prepare_approval", ...)
        end,
        ---Records a typed approval in the current Tool authority port.
        --@param ... any Approval record arguments.
        --@return any result Current approval record result.
        record_approval = function(...)
            return invoke("tools", "record_approval", ...)
        end,
        ---Returns the active current-generation Tool handle.
        --@param ... any Tool handle query arguments.
        --@return any result Active Tool handle or false.
        active_handle = function(...) return invoke("tools", "active_handle", ...) end,
    }, "generation-bound Tool port")
    local reviews = readonly({
        ---Starts a no-tool review on the current generation.
        --@param ... any Review start arguments.
        --@return any result Current review start result.
        start = function(...) return invoke("reviews", "start", ...) end,
        ---Cancels a current-generation review.
        --@param ... any Review cancel arguments.
        --@return any result Current review cancel result.
        cancel = function(...) return invoke("reviews", "cancel", ...) end,
        ---Polls current-generation review events.
        --@param ... any Review poll arguments.
        --@return any result Current review poll result.
        poll = function(...) return invoke("reviews", "poll", ...) end,
        ---Reads the current-generation review status.
        --@param ... any Review status arguments.
        --@return any result Current review status result.
        status = function(...) return invoke("reviews", "status", ...) end,
    }, "generation-bound review port")
    local compaction = readonly({
        ---Starts a compaction Model request on the current generation.
        --@param ... any Compaction start arguments.
        --@return any result Current compaction start result.
        start = function(...) return invoke("compaction", "start", ...) end,
        ---Cancels a current-generation compaction Model request.
        --@param ... any Compaction cancel arguments.
        --@return any result Current compaction cancel result.
        cancel = function(...) return invoke("compaction", "cancel", ...) end,
        ---Polls current-generation compaction Model events.
        --@param ... any Compaction poll arguments.
        --@return any result Current compaction poll result.
        poll = function(...) return invoke("compaction", "poll", ...) end,
        ---Reads current-generation compaction Model status.
        --@param ... any Compaction status arguments.
        --@return any result Current compaction status result.
        status = function(...) return invoke("compaction", "status", ...) end,
    }, "generation-bound compaction Model port")
    local catalog = {}

    ---Checks all generation-bound effects before replacing turn ports.
    --@param none No arguments.
    --@return boolean idle Whether Model, Tool, review, and compaction are idle.
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

    ---Swaps in a fully constructed turn generation only while all effects are idle.
    --@param candidate table Next generation-bound activity port set.
    --@return boolean|nil replaced True after atomic catalog replacement.
    --@return table|nil err Structured busy or invalid-port failure.
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

    ---Returns the ConfigGeneration bound to the current turn ports.
    --@param none No arguments.
    --@return table generation Current ConfigGeneration.
    function catalog.generation()
        return current.generation
    end

    ---Returns the frozen compaction Model/Prompt binding for current ports.
    --@param none No arguments.
    --@return table binding Current generation compaction binding.
    function catalog.compaction_binding()
        return current.compaction_binding
    end

    catalog.model = model
    catalog.tools = tools
    catalog.reviews = reviews
    catalog.compaction = compaction
    return readonly(catalog, "production turn catalog")
end

---Bounds prompt bytes charged against the compaction Model window.
--@param generation table Current ConfigGeneration.
--@param binding table Frozen compaction Model and Prompt selection.
--@return integer|nil bytes Conservative prompt byte upper bound.
--@return table|nil err Structured missing-snapshot failure.
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

---Builds bounded compaction policy from Model window and recovery history.
--@param generation table Current ConfigGeneration.
--@param binding table Frozen compaction Model binding.
--@param initial_serial integer Restored compaction serial.
--@param initial_automatic_failure_count integer Restored automatic failure streak.
--@param automatic_failure_history_complete boolean Whether recovery saw full history.
--@return table|nil options Production compaction limits and trigger policy.
--@return table|nil err Structured capacity or snapshot failure.
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
--@param composed table Runtime Context, publication, and Model services.
--@param catalog table Generation-bound turn activity catalog.
--@param loop table Owning AgentLoop external-receipt gate.
--@param clock table Monotonic Agent clock port.
--@return table|nil owner Read-only production compaction owner.
--@return table|nil err Structured missing-port failure.
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

    ---Halts Runtime after an ambiguous compaction journal barrier.
    --@param reason string Stable ambiguity reason.
    --@param fallback table|nil Original journal failure.
    --@return boolean accepted Always false after fail-stop.
    --@return table err Runtime barrier or original failure.
    local function fail_compaction_barrier(reason, fallback)
        local _, barrier_error = loop:fail_compaction_barrier(reason)
        return false, barrier_error or fallback
    end

    local journal = {}
    for _, method in ipairs({
        "commit_intent", "commit_response", "commit_rejection",
        "publish", "commit_correction",
    }) do
        ---Commits one compaction Fact and adopts its exact Runtime receipt.
        --@param record table Typed compaction journal operation.
        --@return boolean committed True after durable adoption.
        --@return table receipt_or_error Exact receipt or structured failure.
        journal[method] = function(record)
            local called, committed, receipt = pcall(
                durable_journal[method],
                record
            )
            if called and committed ~= true and method == "commit_intent"
                and record.attempt == 1 and type(receipt) == "table"
                and receipt.code == "ContextCapacity" and receipt.publication_started == false
            then
                return false, receipt
            end
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

    ---Builds or reuses compaction service for the current ConfigGeneration.
    --@param snapshot table Durable Context compaction snapshot.
    --@param binding table Frozen Model/Prompt generation binding.
    --@return table|nil service Current compaction service.
    --@return table|nil err Structured generation or service failure.
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
                ---Conservatively charges one token per source byte on old targets.
                --@param bytes string Exact compaction source bytes.
                --@return integer|nil tokens Conservative token count.
                --@return table|nil err Structured non-string source failure.
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

    ---Captures the AgentLoop's exact Context generation, sequence, and view.
    --@param none No arguments.
    --@return table|nil status Current AgentLoop status.
    --@return table observed_or_error Immutable waterline or structured failure.
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

    ---Binds durable Context facts and current Model window to one compaction input.
    --@param mode string Manual or automatic compaction mode.
    --@return table|nil prepared Exact observed input and snapshot.
    --@return table|nil err Structured stale or capacity failure.
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

    ---Normalizes a compaction decision or terminal record into its outcome.
    --@param result table|any Compaction service result.
    --@return string|nil outcome Known settlement outcome, if terminal.
    local function result_outcome(result)
        if type(result) ~= "table" then return nil end
        if type(result.outcome) == "string" then return result.outcome end
        if result.decision == "no_op" then return "no_op" end
        if result.decision == "fits" then return "fits" end
        if result.decision == "suppressed" then return "suppressed" end
        if result.decision == "waiting_user" then return "waiting_user" end
        return nil
    end

    ---Closes the Runtime compaction gate after exact terminal publication.
    --@param result table Compaction service result.
    --@return table|false|nil settlement Bound terminal result, false if still active.
    --@return table|nil err Structured Runtime settlement failure.
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

    ---Admits a single manual or automatic compaction lifecycle.
    --@param self table Production compaction owner.
    --@param mode string Manual or automatic mode.
    --@return table|nil admission Active request or terminal result.
    --@return table|nil err Structured busy, snapshot, or journal failure.
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
            local release_outcome = (mode == "automatic"
                or (type(begin_error) == "table" and begin_error.code == "ContextCapacity"
                    and begin_error.publication_started == false))
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

    ---Polls bounded compaction Model events and settles terminal outcomes.
    --@param self table Production compaction owner.
    --@return table|nil batch Progress events and current status.
    --@return table|nil err Structured activity or journal failure.
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

    ---Cancels the active compaction request through its owning service.
    --@param self table Production compaction owner.
    --@param reason string Cancellation reason.
    --@return table|nil result Terminal or pending cancellation state.
    --@return table|nil err Structured missing-request or settlement failure.
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

    ---Reports current compaction lifecycle and automatic circuit state.
    --@param self table Production compaction owner.
    --@return table status Immutable compaction owner projection.
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

    ---Closes compaction admission, cancelling an active request first.
    --@param self table Production compaction owner.
    --@param reason string|nil Close cancellation reason.
    --@return boolean|table|nil closed True, false if already closed, or pending result.
    --@return table|nil err Structured cancellation failure.
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

---Builds release-bounded HTTP transport options from bundled runtime paths.
--@param layout table Observed executable and bundled component layout.
--@return table options Network limits and bundled curl/CA paths.
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

---Builds the strict INI and runtime bounds for ConfigGeneration parsing.
--@param ca_bundle_path string Bundled trust store path.
--@return table options Config schema, limits, and defaults.
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

---Checks a complete native filesystem object identity record.
--@param value any Candidate identity.
--@param expected_kind string|nil Required object kind, if any.
--@return boolean exact Whether all identity fields are present and admissible.
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

---Wraps native Workspace inspection with path and identity validation.
--@param native table Bundled native module with workspace_inspect.
--@return table port Read-only Workspace inspection service.
local function workspace_port(native)
    return readonly({
        ---Inspects an enterable Workspace and freezes its native object identity.
        --@param requested string User-requested Workspace path.
        --@return table|nil observation Canonical path and exact directory identity.
        --@return table|nil err Structured invalid or unavailable Workspace failure.
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

---Composes bounded Context schema, storage, path, prompt, and catalog services.
--@param native table Bundled native module.
--@param filesystem table Bounded native filesystem port.
--@param data_root string Application-owned data directory.
--@param platform_kind string Linux or Windows path style.
--@param layout table|nil Observed executable and optional tools layout.
--@return table|nil services Read-only Context service bundle.
--@return table|nil err Structured dependency or construction failure.
local function build_context_services(native, filesystem, data_root, platform_kind, layout)
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
        maximum_bytes = 64 * 1024 * 1024,
        maximum_depth = 32,
        maximum_elements = 131072,
        maximum_attributes_per_element = 8,
        maximum_text_node_bytes = 524288,
        maximum_total_text_bytes = 16 * 1024 * 1024,
        maximum_sax_events = 393216,
        maximum_context_events = 4096,
        maximum_carrier_bytes = 262144,
        maximum_chunk_bytes = 65536,
    })
    if not codec then return nil, codec_error end
    local schema, schema_error = context.new({
        xml = codec,
        safety = safety_service,
        maximum_name_bytes = 256,
        maximum_identifier_bytes = 256,
        maximum_field_name_bytes = 64,
        maximum_field_bytes = 262144,
        maximum_events = 4096,
        maximum_compaction_records = 64,
        maximum_export_bytes = 64 * 1024 * 1024,
    })
    if not schema then return nil, schema_error end
    local store, store_error = context.new_store(schema, { filesystem = filesystem }, {
        maximum_context_bytes = 64 * 1024 * 1024,
        maximum_lock_hostname_bytes = 64,
        maximum_temp_nonce_bytes = 32,
        context_permissions = 384,
        lock_permissions = 384,
        settlement_reserve = {
            model_calls = MODEL_ADAPTER_OPTIONS.maximum_tool_calls,
            model_bytes = MODEL_ACTIVITY_OPTIONS.maximum_canonical_body_bytes,
            message_bytes = AGENT_RELEASE_OPTIONS.runtime.hard_caps.message_bytes,
            result_bytes = AGENT_RELEASE_OPTIONS.runtime.hard_caps.result_bytes,
        },
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
        environment = layout and tools.describe_environment(filesystem, layout, platform_kind) or nil,
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

---Reads one bounded ordinary file through the native stream port.
--@param filesystem table Native filesystem port.
--@param path string Physical file path.
--@param maximum_bytes integer Maximum admitted file size.
--@return string|nil bytes Complete file bytes.
--@return table identity_or_error Observed file identity or structured failure.
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

---Hashes a bounded file for a local self-test fixture.
--@param filesystem table Native filesystem port.
--@param safety_service table Digest service.
--@param path string Physical file path.
--@param maximum_bytes integer Maximum admitted file size.
--@return string|nil digest File digest.
--@return table|nil err Structured read or digest failure.
local function file_digest(filesystem, safety_service, path, maximum_bytes)
    local bytes, read_error = read_file_bytes(filesystem, path, maximum_bytes)
    if not bytes then return nil, read_error end
    return safety_service.digest(bytes)
end

---Creates a normalized offline self-test check result.
--@param outcome string Passed, failed, skipped, or partial outcome.
--@param summary string Human-readable check summary.
--@param evidence table|nil Bounded evidence array.
--@return table result Offline check with zero online requests and fixes.
local function check_result(outcome, summary, evidence)
    return {
        outcome = outcome,
        summary = summary,
        evidence = evidence or {},
        online_requests = 0,
        auto_fixes = 0,
    }
end

---Calls one Context catalog method and normalizes port exceptions.
--@param port table Scanner or catalog service.
--@param method string Port method name.
--@param ... any Forwarded method arguments.
--@return boolean ok Whether the port accepted the call.
--@return any value_or_error Port value or structured failure.
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

---Scans Context catalog rings into bounded rows and optional target bindings.
--@param context_services table Context scanner, catalog, and path services.
--@param capture_targets boolean Whether to retain target credentials.
--@return table|nil observation Rows, scan completeness, and optional targets.
--@return table|nil err Structured catalog failure.
local function observe_context_catalog(context_services, capture_targets)
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
    local targets = {}
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
            if capture_targets then
                local selection, selection_error = context_services.catalog.capture_target(candidate)
                if not selection then
                    complete = false
                    partial_reason = selection_error and selection_error.code or "target-capture"
                    break
                end
                targets[#targets + 1] = selection
            end
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
        targets = capture_targets and targets or nil,
    }
end

local CATALOG_STATE_ORDER = {
    valid = 1,
    corrupt = 2,
    unavailable = 3,
    changed = 4,
}

---Builds a deterministic comparator with valid Contexts before failures.
--@param path_service table Canonical logical-path comparison service.
--@param sort_by string Created, updated, or name field.
--@param direction string Ascending or descending order.
--@return function compare Comparator for catalog rows.
local function catalog_row_order(path_service, sort_by, direction)
    ---Orders two catalog rows by state, configured field, then logical path.
    --@param left table First catalog row.
    --@param right table Second catalog row.
    --@return boolean before Whether left precedes right.
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

---Projects one sorted and bounded recent or full Context catalog page.
--@param context_services table Context path comparison service.
--@param observation table Scanned catalog rows.
--@param generation table|nil Current ConfigGeneration list preferences.
--@param view string Recent or full catalog view.
--@return table page Rows, counts, sort order, and truncation status.
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

---Exercises publication in private, uniquely named fixtures on this filesystem.
-- A successful probe is runtime evidence, never power-loss or release qualification.
--@param runtime table Production backend, data root, and safety service.
--@return table result Publication probe outcome and bounded evidence.
function M.check_publication(runtime)
    local fs = runtime.backend.filesystem
    local root = runtime.layout.data_root
    local random = runtime.backend.system.secure_random(16)
    if type(random) ~= "string" or #random ~= 16 then
        return check_result("failed", "publication probe randomness is unavailable")
    end
    ---Encodes one random byte into the private fixture's hexadecimal suffix.
    --@param byte string One secure random byte.
    --@return string hex Two lowercase hexadecimal digits.
    local suffix = random:gsub(".", function(byte) return string.format("%02x", byte:byte()) end)
    local prefix = root .. "/.yaca-self-test-" .. suffix
    local owned, handles = {}, {}
    ---Requires a native fixture operation to succeed or raises its stable code.
    --@param ok boolean Native operation success flag.
    --@param value any Native result or structured failure.
    --@return any value Successful native result.
    local function need(ok, value)
        if not ok then error(type(value) == "table" and value.code or "PublicationProbeFailed", 0) end
        return value
    end
    ---Creates, writes, and flushes one private publication fixture.
    --@param path string New fixture path.
    --@param bytes string Fixture content.
    --@return table snapshot Direct post-close file observation.
    local function create(path, bytes)
        local missing = need(fs.direct_inspect(path))
        if missing.exists then error("PublicationProbeCollision", 0) end
        local handle = need(fs.direct_create_new(missing, 384))
        handles[handle] = path
        owned[path] = need(fs.stat_identity(handle))
        need(fs.stream_write(handle, bytes))
        owned[path] = need(fs.stat_identity(handle))
        need(fs.flush_file(handle))
        need(fs.close(handle))
        handles[handle] = nil
        return need(fs.direct_inspect(path))
    end
    ---Probes no-replace rename and replacement on private filesystem fixtures.
    --@param none No arguments.
    --@return nil Raises if any fixture step fails.
    local ok, problem = pcall(function()
        local first = create(prefix .. ".old", "publication-before\n")
        local missing = need(fs.direct_inspect(prefix .. ".target"))
        local renamed = need(fs.direct_rename(first, missing))
        owned[prefix .. ".target"], owned[prefix .. ".old"] = renamed, nil
        need(fs.flush_directory(root))
        local temporary = create(prefix .. ".new", "publication-after\n")
        local target = need(fs.direct_inspect(prefix .. ".target"))
        local published = need(fs.direct_replace(temporary, target))
        owned[prefix .. ".target"], owned[prefix .. ".new"] = published, nil
        need(fs.flush_directory(root))
        local bytes, identity = read_file_bytes(fs, prefix .. ".target", 128)
        if not bytes then error(identity.code or "PublicationProbeRead", 0) end
        if identity.volume ~= published.volume or identity.object ~= published.object then
            error("PublicationProbeTargetChanged", 0)
        end
        if bytes ~= "publication-after\n" then error("PublicationProbeMismatch", 0) end
        owned[prefix .. ".target"] = identity
    end)
    local cleaned = true
    for handle, path in pairs(handles) do
        local stated, valid, identity = pcall(fs.stat_identity, handle)
        if stated and valid then owned[path] = identity end
        local called, closed = pcall(fs.close, handle)
        if not called or not closed then cleaned = false end
    end
    for path, identity in pairs(owned) do
        local called, deleted = pcall(fs.delete_verified, path, identity)
        if not called or not deleted then cleaned = false end
    end
    local called, flushed = pcall(fs.flush_directory, root)
    if not called or not flushed then cleaned = false end
    if not cleaned then
        return check_result("unknown", "publication probe cleanup or directory flush could not be verified",
            { "scope=isolated-runtime-probe", "qualification=not-assessed" })
    end
    if not ok then
        return check_result("failed", "publication round-trip failed",
            { "code=" .. safe_diagnostic(problem, 128), "qualification=not-assessed" })
    end
    return check_result("passed", "isolated publication round-trip and cleanup passed",
        { "create-flush-rename-replace-read-delete=passed", "qualification=not-assessed" })
end

---Builds offline platform, package, Context, and publication self-test checks.
--@param runtime table Production backend, layout, and Context services.
--@return function check Offline check callback for the self-test runner.
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

    ---Checks whether a required package path is an ordinary file.
    --@param path string Physical package path.
    --@return boolean regular Whether a regular file was observed.
    --@return table|nil identity_or_error Native identity or failure.
    local function stat_file(path)
        local stated, value = filesystem.stat_identity(path)
        return stated and value.kind == "file", value
    end

    ---Scans Context rows and verifies each distinct recorded Workspace root.
    --@param specification table Frozen self-test snapshot identity.
    --@return table|nil observation Catalog and Workspace-root counts.
    --@return table|nil err Structured catalog failure.
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

    ---Reuses the catalog scan for one exact self-test snapshot.
    --@param specification table Frozen self-test snapshot identity.
    --@return table|nil observation Current catalog observation.
    --@return table|nil err Structured scan failure.
    local function current_catalog(specification)
        if catalog_snapshot_id ~= specification.snapshot_id then
            return scan_catalog(specification)
        end
        return catalog_observation, catalog_observation_error
    end

    ---Evaluates one named offline self-test against observed runtime facts.
    --@param specification table Selected check and frozen snapshot.
    --@return table result Offline check outcome and evidence.
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
            if config.available == false
                and config.error and config.error.code == "ConfigMissing"
            then
                return check_result("warning",
                    "configuration is not initialized yet", {
                        "config=absent",
                        "next=run --model-repl to create one",
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
                return check_result("failed", "configuration source cannot be verified")
            end
            if config.available == false
                and config.error and config.error.code == "ConfigMissing"
            then
                return check_result("warning",
                    "configuration is not initialized yet", {
                        "config=absent",
                    })
            end
            return check_result("failed", "configuration source cannot be verified")
        end
        if id == "ST1-ATOMIC-WRITE" then
            local capabilities = filesystem.capabilities
            if capabilities.atomic_replace_candidate
                and capabilities.rename_no_replace_candidate
                and capabilities.verified_delete_candidate
            then
                return M.check_publication(runtime)
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

local SELF_TEST_ONLINE_LIMITS = {
    poll_budget = 32,
    pump_slice_ms = 10,
    capability_timeout_ms = 90000,
    semantic_timeout_ms = 180000,
    cancel_drain_ms = 15000,
    connect_timeout_ms = 30000,
    capability_output_tokens = 1024,
    semantic_output_tokens = 2048,
}

local SELF_TEST_CAPABILITY_INSTRUCTIONS = {
    ["ST2-MODEL-TRANSPORT"] = "This is a connectivity probe. Reply with the single word READY.",
    ["ST2-MODEL-AUTH"] = "This is a credential probe. Reply with the single word READY.",
    ["ST2-MODEL-WIRE"] = "This is a protocol probe. Reply with the single word READY.",
    ["ST2-MODEL-STREAM"] = "This is a streaming probe. Reply with exactly: STREAM CHECK OK.",
    ["ST2-MODEL-TOOLS"] = "This request carries an inert tool schema. Do not call any tool. Reply with the single word READY.",
    ["ST2-MODEL-CONTROL"] = 'This is a tool-carrier probe. Call the function list with arguments {"path":".","depth":1,"page_size":1} exactly once. The tool is inert and will not run.',
    ["ST2-MODEL-USAGE-CANCEL"] = "This is a cancellation probe. Reply with the single word READY.",
}

---Creates a normalized online self-test result with explicit request count.
--@param outcome string Check outcome.
--@param summary string Human-readable finding.
--@param evidence table|nil Bounded evidence lines.
--@param online_requests integer|nil Started provider request count.
--@return table result Online check outcome with no automatic fixes.
local function online_check_result(outcome, summary, evidence, online_requests)
    return {
        outcome = outcome,
        summary = summary,
        evidence = evidence or {},
        online_requests = online_requests or 0,
        auto_fixes = 0,
    }
end

---Formats a bounded ASCII self-test evidence key and value.
--@param label string Evidence field name.
--@param value any Observed value to display.
--@return string line Safe evidence line.
local function evidence_line(label, value)
    return ascii_diagnostic(label .. "=" .. tostring(value), 200)
end

---Revalidates the confirmed Model endpoint and ConfigGeneration before a request.
--@param composed table Production Config, Model, and network services.
--@param specification table Frozen self-test Model and snapshot ID.
--@return table|nil generation Current matching ConfigGeneration.
--@return string|nil code Stable binding failure code.
--@return string|nil message Binding failure explanation.
local function resolve_self_test_generation(composed, specification)
    if type(composed.config) ~= "table"
        or type(composed.config.reload_file) ~= "function"
        or type(composed.layout) ~= "table"
        or type(composed.layout.config_path) ~= "string"
        or type(composed.model_adapter) ~= "table"
        or type(composed.network) ~= "table"
        or type(composed.contexts) ~= "table"
        or type(composed.contexts.safety) ~= "table"
        or type(composed.contexts.prompt) ~= "table"
        or type(composed.contexts.tool_registry) ~= "table"
    then
        return nil, "SelfTestUnavailable", "production self-test ports are incomplete"
    end
    local generation = composed.config.reload_file(composed.layout.config_path)
    if not generation then
        return nil, "ConfigUnavailable", "the configuration could not be reloaded for the online check"
    end
    local model = generation.models and generation.models[specification.model.id]
    if type(model) ~= "table" or model.enabled ~= true then
        return nil, "ModelUnavailable", "the Model is no longer enabled in the current configuration"
    end
    if model.endpoint ~= specification.model.endpoint then
        return nil, "ModelChanged", "the Model endpoint changed after the self-test snapshot"
    end
    if generation.id ~= specification.snapshot_id then
        return nil, "ConfigChanged", "configuration changed after the online test was confirmed"
    end
    return generation
end

-- Starts one purpose=self-test Model request through the production adapter,
-- transport, proxy, and CA policy, then pumps it to a typed terminal state.
-- cancel_after_start requests cancellation before the first poll so the
-- cancellation path itself is exercised. Returns an observation table whose
-- online_requests counts started provider attempts.
--@param composed table Production Model, network, Context, and clock services.
--@param specification table Confirmed self-test check and Model snapshot.
--@param definition table Probe phase, prompt, tool set, timeout, and cancel policy.
--@return table|nil observation Canonical events and terminal response.
--@return string|nil code Stable pre-request binding failure code.
--@return string|nil message Pre-request binding failure explanation.
local function run_self_test_model_request(composed, specification, definition)
    local generation, code, message
    generation, code, message = resolve_self_test_generation(composed, specification)
    if not generation then
        return nil, code, message
    end
    local model = generation.models[specification.model.id]
    local model_module = require("model")
    local builder, builder_error = model_module.new_self_test_request_builder({
        adapter = composed.model_adapter,
        prompt = composed.contexts.prompt,
        generation = generation,
        tool_registry = composed.contexts.tool_registry,
        safety = composed.contexts.safety,
    }, {
        model_name = specification.model.id,
        phase = definition.phase,
        synthetic_observation = definition.instruction,
        tool_set = definition.tool_set,
        default_connect_timeout_ms = SELF_TEST_ONLINE_LIMITS.connect_timeout_ms,
        default_request_timeout_ms = definition.timeout_ms,
        maximum_request_time_ms = definition.timeout_ms,
        default_retry_base_delay_ms = 1000,
        default_max_output_tokens = definition.max_output_tokens,
    })
    if not builder then
        return nil, "SelfTestRequestInvalid",
            "self-test request preparation failed: "
            .. safe_diagnostic(builder_error and builder_error.code or "?", 96)
    end
    local activity_options = copy_plain(composed.model_activity_options, {})
    if not activity_options then
        return nil, "SelfTestRequestInvalid", "self-test activity limits are unavailable"
    end
    activity_options.identity_namespace = "self-test"
    local activity, activity_error = model_module.new_activity({
        adapter = composed.model_adapter,
        transport = composed.network,
        safety = composed.contexts.safety,
        clock = composed.backend.clock_port,
        requests = builder,
    }, activity_options)
    if not activity then
        return nil, "SelfTestRequestInvalid",
            "self-test Model activity is unavailable: "
            .. safe_diagnostic(activity_error and activity_error.code or "?", 96)
    end
    local clock = composed.backend.clock_port
    local started_at, clock_error
    started_at, clock_error = clock.monotonic_now()
    if type(started_at) ~= "number" then
        return nil, "SelfTestClockFailed", "self-test clock is unavailable"
    end
    local handle, start_error = activity.start({
        request_id = "selftest-" .. string.lower(specification.check.id),
        turn_id = "self-test",
        purpose = "self-test",
        continuation = false,
        view_manifest_ref = builder.snapshots.view,
        progress_identity = "self-test/" .. specification.check.id,
    })
    if not handle then
        return nil, "SelfTestRequestInvalid",
            "self-test Model request could not start: "
            .. safe_diagnostic(start_error and start_error.code or "?", 96)
    end
    local observation = {
        online_requests = 1,
        events = {},
        response = false,
        cancel_requested = false,
        deadline_exceeded = false,
        model = model,
    }
    if definition.cancel_after_start then
        activity.cancel(handle, "self-test-cancel")
        observation.cancel_requested = true
    end
    local deadline_at = started_at + definition.timeout_ms
    local drain_at = deadline_at + SELF_TEST_ONLINE_LIMITS.cancel_drain_ms
    while true do
        local observed_now = clock.monotonic_now()
        if type(observed_now) ~= "number" then
            observation.deadline_exceeded = true
            break
        end
        local batch, poll_error = activity.poll(SELF_TEST_ONLINE_LIMITS.poll_budget)
        if not batch then
            observation.poll_error = poll_error and poll_error.code or "poll-failed"
            break
        end
        for _, item in ipairs(batch) do
            if item.kind == "response" then
                observation.response = item.wrapper
            elseif item.kind == "adapter-event" then
                observation.events[#observation.events + 1] = item.event
            end
        end
        if observation.response then break end
        if observed_now >= (observation.cancel_issued_at and drain_at or deadline_at) then
            if not observation.cancel_issued_at then
                activity.cancel(handle, "self-test-deadline")
                observation.cancel_issued_at = true
                observation.cancel_requested = true
            elseif observed_now >= drain_at then
                observation.deadline_exceeded = true
                break
            end
        end
        if #batch == 0 then
            local slept, sleep_result = pcall(
                clock.sleep_ms,
                SELF_TEST_ONLINE_LIMITS.pump_slice_ms
            )
            if not slept or sleep_result == false then
                observation.deadline_exceeded = true
                break
            end
        end
    end
    return observation
end

---Projects provider events and terminal response into capability facts.
--@param observation table Canonical Model self-test event observation.
--@return table facts Transport, protocol, delta, Tool, usage, and finish facts.
local function classify_self_test_observation(observation)
    local facts = {
        http_status = false,
        connection_error = false,
        protocol_error = false,
        deltas = 0,
        tool_calls = 0,
        usage = false,
        finish_class = false,
        incomplete = false,
        canonical_body = false,
    }
    for _, event in ipairs(observation.events) do
        local kind = event.kind
        if kind == "transport_error" then
            if type(event.status) == "number" then
                facts.http_status = event.status
            else
                facts.connection_error = event.error_id or "transport-failure"
            end
        elseif kind == "protocol_error" then
            facts.protocol_error = event.error_id or "protocol-error"
        elseif kind == "text_delta" or kind == "reasoning_summary_delta"
            or kind == "tool_arguments_delta" then
            facts.deltas = facts.deltas + 1
        elseif kind == "tool_call_complete" then
            facts.tool_calls = facts.tool_calls + 1
        elseif kind == "usage_update" then
            facts.usage = true
        elseif kind == "response_finish" and event.finish_class then
            facts.finish_class = event.finish_class
        end
    end
    local wrapper = observation.response
    if type(wrapper) == "table" and type(wrapper.normalized) == "table" then
        local normalized = wrapper.normalized
        facts.finish_class = normalized.finish_class or facts.finish_class
        facts.incomplete = normalized.incomplete == true
        if type(wrapper.canonical_body) == "string" then
            facts.canonical_body = wrapper.canonical_body
        end
        if type(normalized.tool_calls) == "table" then
            facts.tool_calls = math.max(facts.tool_calls, #normalized.tool_calls)
        end
        if normalized.usage then facts.usage = true end
    end
    return facts
end

---Reports a pre-request Model binding failure without claiming online traffic.
--@param code string Stable binding failure code.
--@param message string Human-readable binding failure.
--@return table result Failed online check with zero requests.
local function self_test_binding_failure(code, message)
    return online_check_result("failed", message, { evidence_line("reason", code) }, 0)
end

---Reports a provider transport failure with observed terminal evidence.
--@param code string Check identity retained by the caller.
--@param facts table Classified transport and finish observations.
--@return table result Failed online check with one started request.
local function self_test_transport_failure(code, facts)
    return online_check_result(
        "failed",
        "the Model transport failed before a provider response",
        {
            evidence_line("transport", facts.connection_error),
            evidence_line("finish", facts.finish_class or "none"),
        },
        1
    )
end

---Evaluates one Stage 2 capability probe from canonical provider facts.
--@param check_id string Stage 2 Model check identity.
--@param observation table Canonical activity events and terminal response.
--@param model table Confirmed Model capabilities.
--@return table result Passed, warning, or failed capability outcome.
function M.evaluate_self_test_check(check_id, observation, model)
    local facts = classify_self_test_observation(observation)
    if not observation.response and observation.deadline_exceeded then
        return online_check_result(
            "failed",
            "the online Model request did not reach a terminal state in time",
            { evidence_line("timeout", check_id) },
            1
        )
    end
    if not observation.response and observation.poll_error then
        return online_check_result(
            "failed",
            "the online Model request ended in an internal failure",
            { evidence_line("internal", observation.poll_error) },
            1
        )
    end
    if facts.connection_error and not (check_id == "ST2-MODEL-USAGE-CANCEL"
        and observation.cancel_requested and facts.finish_class == "cancelled") then
        return self_test_transport_failure(check_id, facts)
    end
    if check_id == "ST2-MODEL-TRANSPORT" then
        if facts.http_status then
            return online_check_result(
                "passed",
                "the provider endpoint answered the transport probe",
                {
                    evidence_line("http", facts.http_status),
                    evidence_line("finish", facts.finish_class or "none"),
                },
                1
            )
        end
        return online_check_result(
            "passed",
            "a complete provider response arrived over the configured transport",
            {
                evidence_line("http", "2xx"),
                evidence_line("finish", facts.finish_class or "none"),
            },
            1
        )
    end
    if check_id == "ST2-MODEL-AUTH" then
        if model.key_configured ~= true then
            return online_check_result(
                "failed",
                "the enabled Model has no configured credential",
                { evidence_line("credential", "missing") },
                0
            )
        end
        if facts.http_status == 401 or facts.http_status == 403 then
            return online_check_result(
                "failed",
                "the provider rejected the configured credential",
                { evidence_line("http", facts.http_status) },
                1
            )
        end
        if facts.http_status or facts.finish_class then
            return online_check_result(
                "passed",
                "the configured credential was accepted by the provider",
                {
                    evidence_line("credential", "accepted"),
                    evidence_line("finish", facts.finish_class or "none"),
                },
                1
            )
        end
        return online_check_result(
            "failed",
            "the authentication probe produced no usable provider verdict",
            { evidence_line("finish", facts.finish_class or "none") },
            1
        )
    end
    if check_id == "ST2-MODEL-WIRE" then
        if facts.protocol_error then
            return online_check_result(
                "failed",
                "the provider response violated the adapter protocol",
                { evidence_line("protocol", facts.protocol_error) },
                1
            )
        end
        if facts.http_status then
            return online_check_result(
                "failed",
                "the provider refused the canonical wire request",
                {
                    evidence_line("http", facts.http_status),
                    evidence_line("finish", facts.finish_class or "none"),
                },
                1
            )
        end
        if facts.finish_class and not facts.incomplete then
            return online_check_result(
                "passed",
                "the provider answered with a complete canonical response",
                {
                    evidence_line("finish", facts.finish_class),
                    evidence_line("protocol", model.protocol),
                },
                1
            )
        end
        return online_check_result(
            "failed",
            "the provider response was incomplete",
            { evidence_line("finish", facts.finish_class or "none") },
            1
        )
    end
    if check_id == "ST2-MODEL-STREAM" then
        local mode = model.streaming
        if facts.http_status or facts.incomplete or facts.protocol_error then
            return online_check_result(
                "failed",
                "the streaming probe did not produce a complete response",
                {
                    evidence_line("mode", mode),
                    evidence_line("http", facts.http_status or "none"),
                    evidence_line("protocol", facts.protocol_error or "none"),
                },
                1
            )
        end
        if mode == "off" then
            return online_check_result(
                "passed",
                "non-streaming responses parse completely as configured",
                {
                    evidence_line("mode", "off"),
                    evidence_line("finish", facts.finish_class or "none"),
                },
                1
            )
        end
        if facts.deltas > 0 then
            return online_check_result(
                "passed",
                "streamed provider events arrived and parsed canonically",
                {
                    evidence_line("mode", mode),
                    evidence_line("streamed-events", facts.deltas),
                },
                1
            )
        end
        if mode == "try" then
            return online_check_result(
                "passed",
                "try streaming completed through its single non-streaming fallback",
                {
                    evidence_line("mode", "try"),
                    evidence_line("fallback", "true"),
                    evidence_line("finish", facts.finish_class or "none"),
                },
                1
            )
        end
        return online_check_result(
            "failed",
            "forced streaming produced no streamed provider events",
            {
                evidence_line("mode", "force"),
                evidence_line("streamed-events", 0),
            },
            1
        )
    end
    if check_id == "ST2-MODEL-TOOLS" then
        if facts.http_status or facts.protocol_error then
            return online_check_result(
                "failed",
                "the provider rejected the request carrying the tool schema",
                {
                    evidence_line("http", facts.http_status or "none"),
                    evidence_line("protocol", facts.protocol_error or "none"),
                },
                1
            )
        end
        if facts.finish_class and not facts.incomplete then
            return online_check_result(
                "passed",
                "the provider accepted the inert production tool schema round-trip",
                {
                    evidence_line("tools", "accepted"),
                    evidence_line("registry", "production-v1"),
                    evidence_line("finish", facts.finish_class),
                },
                1
            )
        end
        return online_check_result(
            "failed",
            "the tool schema probe response was incomplete",
            { evidence_line("finish", facts.finish_class or "none") },
            1
        )
    end
    if check_id == "ST2-MODEL-CONTROL" then
        local normalized = observation.response and observation.response.normalized
        local calls = normalized and normalized.tool_calls
        if not facts.incomplete and not facts.protocol_error
            and facts.finish_class == "tool_calls"
            and normalized and normalized.tool_calls_validated == true
            and type(calls) == "table" and #calls == 1
            and calls[1].name == "list"
            and calls[1].canonical_arguments == '{"depth":1,"page_size":1,"path":"."}' then
            return online_check_result(
                "passed",
                "the provider tool-call carrier round-tripped with schema-valid arguments",
                {
                    evidence_line("carrier", "provider-tool-call"),
                    evidence_line("calls", facts.tool_calls),
                    evidence_line("schema", "validated"),
                },
                1
            )
        end
        if facts.http_status or facts.protocol_error then
            return online_check_result(
                "failed",
                "the control carrier probe failed before a provider verdict",
                {
                    evidence_line("http", facts.http_status or "none"),
                    evidence_line("protocol", facts.protocol_error or "none"),
                },
                1
            )
        end
        return online_check_result(
            "failed",
            "the Model did not return the exact requested inert tool call",
            {
                evidence_line("carrier", "absent"),
                evidence_line("finish", facts.finish_class or "none"),
            },
            1
        )
    end
    if check_id == "ST2-MODEL-USAGE-CANCEL" then
        if facts.finish_class == "cancelled" then
            return online_check_result(
                "passed",
                "cancellation terminated the request with a typed cancelled state",
                {
                    evidence_line("cancel", "typed"),
                    evidence_line("usage", facts.usage and "parsed" or "absent-allowed"),
                },
                1
            )
        end
        if facts.http_status or facts.protocol_error or facts.connection_error then
            return online_check_result(
                "failed",
                "the cancellation probe failed before a terminal verdict",
                {
                    evidence_line("http", facts.http_status or "none"),
                    evidence_line("protocol", facts.protocol_error or "none"),
                },
                1
            )
        end
        if facts.usage then
            return online_check_result(
                "passed",
                "usage accounting parsed and the request ended typed",
                {
                    evidence_line("cancel", "completed-before-effect"),
                    evidence_line("usage", "parsed"),
                },
                1
            )
        end
        return online_check_result(
            "warning",
            "the request completed before cancellation and reported no usage",
            {
                evidence_line("cancel", "completed-before-effect"),
                evidence_line("usage", "absent"),
            },
            1
        )
    end
    return online_check_result(
        "failed",
        "the online Model adapter has no composed behavior for this check",
        { evidence_line("check", check_id) },
        0
    )
end

---Composes the production online Stage 2 Model port. Every admitted check
---performs one real provider request through the production adapter and
---transport; no Tool executes and no configuration is mutated.
--@param composed table Production Model, network, Config, and Context services.
--@return function check Stage 2 online check callback.
local function build_online_model_self_test(composed)
    ---Runs one confirmed capability probe and evaluates its canonical facts.
    --@param specification table Selected check and frozen Model snapshot.
    --@return table result Normalized online capability result.
    return function(specification)
        local check_id = specification.check.id
        local instruction = SELF_TEST_CAPABILITY_INSTRUCTIONS[check_id]
        if not instruction then
            return online_check_result(
                "failed",
                "the online Model adapter has no instruction for this check",
                { evidence_line("check", check_id) },
                0
            )
        end
        local called, observation, code, message = pcall(
            run_self_test_model_request,
            composed,
            specification,
            {
                phase = "capability",
                instruction = instruction,
                tool_set = (check_id == "ST2-MODEL-TOOLS"
                    or check_id == "ST2-MODEL-CONTROL") and "production" or "none",
                cancel_after_start = check_id == "ST2-MODEL-USAGE-CANCEL",
                timeout_ms = SELF_TEST_ONLINE_LIMITS.capability_timeout_ms,
                max_output_tokens = SELF_TEST_ONLINE_LIMITS.capability_output_tokens,
            }
        )
        if not called then
            return online_check_result(
                "failed",
                "the online Model check raised an internal failure",
                { evidence_line("internal", "exception") },
                0
            )
        end
        if not observation then
            return self_test_binding_failure(code, message)
        end
        local called_evaluation, evaluated = pcall(
            M.evaluate_self_test_check,
            check_id,
            observation,
            observation.model
        )
        if not called_evaluation or type(evaluated) ~= "table" then
            return online_check_result(
                "failed",
                "the online Model check could not be evaluated",
                { evidence_line("internal", "evaluation") },
                observation.online_requests
            )
        end
        return evaluated
    end
end

---Runs a confirmed connection probe against one saved configuration generation.
--@param composed table Production Model self-test services.
--@param name string Selected Model name.
--@param generation table Confirmed ConfigGeneration.
--@return table result Wire connection probe outcome.
function M.check_model_connection(composed, name, generation)
    return build_online_model_self_test(composed)({
        check = { id = "ST2-MODEL-WIRE" },
        model = { id = name, endpoint = generation.models[name].endpoint },
        snapshot_id = generation.id,
    })
end

---Bounds a scalar before including it in an advisory projection.
--@param value any Config scalar value.
--@param maximum integer Maximum retained bytes.
--@return string text Bounded display value.
local function bounded_value(value, maximum)
    local text = tostring(value)
    if #text > maximum then text = text:sub(1, maximum) .. "..." end
    return text
end

-- Builds the bounded, secret-free projection each Stage 3 advisory review
-- quotes to the confirmed Model. The projection is bound to the same frozen
-- self-test snapshot the run started from.
--@param check_id string Stage 3 semantic check identity.
--@param snapshot table Frozen self-test Config snapshot.
--@return string|nil instruction Bounded advisory prompt or nil when unavailable.
local function self_test_semantic_observation(check_id, snapshot)
    local config = type(snapshot) == "table" and snapshot.config or nil
    if type(config) ~= "table" or config.available ~= true
        or type(config.generation) ~= "table"
    then
        return nil
    end
    local generation = config.generation
    local lines = {}
    if check_id == "ST3-CONFIG-SEMANTICS" then
        local general, network, exec = generation.general or {}, {}
        network = generation.network or {}
        exec = generation.exec or {}
        local agent = generation.agent or {}
        local scalars = {
            { "General.StartupSelfTest", general.startup_self_test },
            { "General.AutoRenameInterval", general.auto_rename_interval },
            { "Network.ConnectTimeoutMs", network.connect_timeout_ms },
            { "Network.RequestTimeoutMs", network.request_timeout_ms },
            { "Network.RetryCount", network.retry_count },
            { "Network.FollowProxy", network.follow_proxy },
            { "Network.NoProxy", network.no_proxy },
            { "Exec.EnvironmentMode", exec.environment_mode },
            { "Exec.MaxOutputKb", exec.max_output_kb },
            { "Exec.TimeoutMs", exec.timeout_ms },
            { "Agent.ActionReviewEnabled", agent.action_review_enabled },
            { "Agent.ActionReviewModel", agent.action_review_model },
            { "Agent.TerminationReviewModel", agent.termination_review_model },
            { "Agent.MaxTurnModelRequests", agent.max_turn_model_requests },
            { "Agent.MaxTurnToolCalls", agent.max_turn_tool_calls },
        }
        lines[#lines + 1] = "scope: general/network/exec/agent scalar settings"
        for _, item in ipairs(scalars) do
            lines[#lines + 1] = item[1] .. " = " .. bounded_value(item[2], 96)
        end
    elseif check_id == "ST3-PERMISSION-SEMANTICS" then
        lines[#lines + 1] = "scope: permission profiles"
        for _, name in ipairs(generation.permission_order or {}) do
            local permission = generation.permissions[name]
            if type(permission) == "table" then
                lines[#lines + 1] = "Permission." .. name
                    .. " read=" .. bounded_value(permission.read, 24)
                    .. " write=" .. bounded_value(permission.write, 24)
                    .. " delete=" .. bounded_value(permission.delete, 24)
                    .. " shell=" .. bounded_value(permission.shell, 24)
                    .. " outside=" .. bounded_value(permission.outside_workspace, 24)
                lines[#lines + 1] = "  description: "
                    .. bounded_value(permission.description, 200)
            end
        end
    elseif check_id == "ST3-NAMING-AND-SPELLING" then
        lines[#lines + 1] = "scope: names, descriptions, and spellings"
        for _, name in ipairs(generation.model_order or {}) do
            local model = generation.models[name]
            if type(model) == "table" then
                lines[#lines + 1] = "Model." .. name
                    .. " remote=" .. bounded_value(model.remote_model, 96)
                    .. " enabled=" .. bounded_value(model.enabled, 12)
                lines[#lines + 1] = "  description: "
                    .. bounded_value(model.description, 200)
            end
        end
        for _, name in ipairs(generation.permission_order or {}) do
            local permission = generation.permissions[name]
            if type(permission) == "table" then
                lines[#lines + 1] = "Permission." .. name
                lines[#lines + 1] = "  description: "
                    .. bounded_value(permission.description, 200)
            end
        end
    else
        return nil
    end
    local projection = table.concat(lines, "\n")
    if #projection > 12000 then projection = projection:sub(1, 12000) .. "\n..." end
    return "You are reviewing one yaca configuration projection for obvious"
        .. " semantic problems. Reply with plain text only and no other words:"
        .. ' the compact JSON object {"issues":["problem one","problem two"]}'
        .. " listing at most three clear problems, or the exact object"
        .. ' {"issues":[]} when the projection is coherent. Do not call any'
        .. " tool and do not change anything.\n\n<projection>\n"
        .. projection
        .. "\n</projection>"
end

---Parses a no-tool Stage 3 advisory response into bounded findings.
--@param observation table Canonical provider events and response.
--@return table result Advisory pass or warning with evidence.
function M.evaluate_self_test_advisory(observation)
    local facts = classify_self_test_observation(observation)
    if not observation.response then
        return online_check_result(
            "warning",
            "the advisory review request did not reach a terminal state",
            { evidence_line("internal", observation.poll_error or "no-response") },
            observation.online_requests
        )
    end
    if facts.connection_error or facts.http_status or facts.protocol_error then
        return online_check_result(
            "warning",
            "the advisory review request failed against the provider",
            {
                evidence_line("transport", facts.connection_error or "none"),
                evidence_line("http", facts.http_status or "none"),
                evidence_line("protocol", facts.protocol_error or "none"),
            },
            observation.online_requests
        )
    end
    if not facts.canonical_body then
        return online_check_result(
            "warning",
            "the advisory review returned no canonical answer body",
            { evidence_line("body", "absent") },
            observation.online_requests
        )
    end
    local json = require("json")
    local codec = json.new({
        maximum_bytes = 65536,
        maximum_depth = 8,
        maximum_nodes = 512,
        maximum_string_bytes = 8192,
        maximum_number_bytes = 32,
    })
    local document = codec and codec.parse(facts.canonical_body)
    local issues = json.kind(document) == "object"
        and json.kind(document.issues) == "array" and document.issues or nil
    if issues then
        if facts.incomplete or #issues > 3 then issues = nil end
        for key in pairs(document) do
            if key ~= "issues" then issues = nil end
        end
        for _, issue in ipairs(document.issues) do
            if type(issue) ~= "string" or issue == "" then issues = nil end
        end
    end
    if not issues then
        return online_check_result(
            "warning",
            "the advisory review answer did not match the expected JSON shape",
            { evidence_line("summary", "unparseable") },
            observation.online_requests
        )
    end
    local evidence = {}
    for index, issue in ipairs(issues) do
        if index > 3 then break end
        if type(issue) == "string" then
            evidence[#evidence + 1] = evidence_line("issue", issue)
        end
    end
    if #issues == 0 then
        return online_check_result(
            "passed",
            "the confirmed Model reviewed the projection and found no issue",
            { evidence_line("review", "no-issue") },
            observation.online_requests
        )
    end
    return online_check_result(
        "warning",
        "the confirmed Model reported configuration issues for review",
        evidence,
        observation.online_requests
    )
end

---Composes the production Stage 3 advisory port. Each check asks one
---confirmed Model to review a bounded projection of the frozen snapshot;
---findings are advisory only and never mutate configuration.
--@param composed table Production Model, network, and Config services.
--@return function check Stage 3 advisory check callback.
local function build_online_advisory_self_test(composed)
    ---Runs one confirmed advisory request against a frozen Config projection.
    --@param specification table Selected Stage 3 check and confirmed Model.
    --@return table result Normalized advisory finding.
    return function(specification)
        local check_id = specification.check.id
        local instruction = self_test_semantic_observation(
            check_id,
            specification.snapshot
        )
        if not instruction then
            return online_check_result(
                "skipped",
                "the advisory projection is unavailable for this check",
                { evidence_line("projection", "unavailable") },
                0
            )
        end
        if type(specification.confirmed_models) ~= "table"
            or #specification.confirmed_models == 0
        then
            return online_check_result(
                "skipped",
                "no confirmed Model is available for the advisory review",
                { evidence_line("models", "none") },
                0
            )
        end
        local target = specification.confirmed_models[1]
        local called, observation = pcall(
            run_self_test_model_request,
            composed,
            {
                check = specification.check,
                model = { id = target.id, endpoint = target.endpoint },
                snapshot_id = specification.snapshot_id,
            },
            {
                phase = "semantic",
                instruction = instruction,
                tool_set = "none",
                cancel_after_start = false,
                timeout_ms = SELF_TEST_ONLINE_LIMITS.semantic_timeout_ms,
                max_output_tokens = SELF_TEST_ONLINE_LIMITS.semantic_output_tokens,
            }
        )
        if not called or not observation then
            return online_check_result(
                "skipped",
                "the advisory review request could not be started",
                { evidence_line("internal", "request") },
                0
            )
        end
        local evaluated, evaluated_result = pcall(M.evaluate_self_test_advisory, observation)
        if not evaluated or type(evaluated_result) ~= "table" then
            return online_check_result(
                "warning",
                "the advisory review could not be evaluated",
                { evidence_line("internal", "evaluation") },
                observation.online_requests
            )
        end
        return evaluated_result
    end
end

---Deletes a newly created fixture only against its currently observed identity.
--@param filesystem table Bounded native filesystem port.
--@param path string Created fixture path.
--@return boolean|nil cleaned Whether the file is absent or verified deleted.
--@return table|nil err Structured deletion failure.
local function cleanup_created_file(filesystem, path)
    local stated, identity = filesystem.stat_identity(path)
    if not stated then
        return type(identity) == "table" and identity.code == "NotFound"
    end
    return filesystem.delete_verified(path, identity)
end

---Creates the adjacent application data directory with durable parent flush.
--@param filesystem table Native filesystem port.
--@param path string Application-owned data root.
--@param parent_path string Outer executable directory to flush.
--@return boolean|nil created True if newly created, false if already present.
--@return table|nil err Structured conflict or durability failure.
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

---Publishes a default Config template through a verified no-replace temporary.
--@param filesystem table Native filesystem port.
--@param layout table Observed application data and Config paths.
--@return table|nil receipt Data-root creation outcome.
--@return table|nil err Structured conflict, validation, or durability failure.
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
    ---Closes and removes a failed Config temporary when identity permits.
    --@param original table Original structured write failure.
    --@return nil No template receipt on failure.
    --@return table err Original or unknown-publication failure.
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

---Builds an offline Config, Model, and Context management router.
--@param filesystem table Native filesystem port.
--@param layout table Observed application Config and data paths.
--@param context_services table|nil Context catalog services.
--@return table service Offline management service.
local function management_service(filesystem, layout, context_services)
    local service = { online = false }
    ---Runs one bootstrap-safe offline management action.
    --@param context table Action, Config state, and optional catalog view.
    --@return table result Management status and evidence.
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
--@param runtime table Admitted native, CLI, target, and argv identity.
--@return table|nil composed Read-only production application and runtime services.
--@return table|nil err Structured layout or adapter construction failure.
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
        runtime.identity.os == "windows" and "windows" or "posix",
        layout
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
            workspace = workspace_port(runtime.native),
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
        contexts = contexts,
        config = config_service,
        model_activity_options = MODEL_ACTIVITY_OPTIONS,
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
            run = build_online_model_self_test(composed),
        },
        advisory = {
            online = true,
            auto_fix = false,
            run = build_online_advisory_self_test(composed),
        },
    }, SELF_TEST_OPTIONS)
    if not self_test then return nil, self_test_error end
    local application_components = {
        platform = {
            ---Returns the platform identity already admitted by native startup.
            --@param none No arguments.
            --@return table identity Admitted OS, architecture, and release target.
            identity = function() return runtime.identity end,
        },
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
            store = contexts.store,
            schema = contexts.schema,
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

local MODEL_SELECTION_LIST_LIMIT = 64
local MODEL_SELECTION_TRANSITION_RESERVE = 4096

---Canonicalizes a Model endpoint into scheme, origin, and route identity.
--@param endpoint string Candidate configured Model endpoint.
--@return table|nil identity Normalized endpoint components.
local function normalized_endpoint_identity(endpoint)
    if type(endpoint) ~= "string" or endpoint == ""
        or endpoint:find("[%z\r\n]") or endpoint:find("#", 1, true)
    then
        return nil
    end
    local scheme, authority, route = endpoint:match(
        "^([A-Za-z][A-Za-z0-9+%.%-]*)://([^/%?]+)(.*)$"
    )
    if not scheme or authority == "" or authority:find("@", 1, true) then
        return nil
    end
    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then return nil end
    authority = authority:lower()
    if (scheme == "http" and authority:match(":80$"))
        or (scheme == "https" and authority:match(":443$"))
    then
        authority = authority:gsub(":%d+$", "")
    end
    if route == "" then route = "/"
    elseif route:sub(1, 1) == "?" then route = "/" .. route end
    return {
        scheme = scheme,
        origin = scheme .. "://" .. authority,
        route = route,
        identity = scheme .. "://" .. authority .. route,
    }
end

---Bounds serializable public preview data without accepting cycles or code.
--@param value any Candidate scalar or table.
--@param state table|nil Recursive seen set and byte/node counters.
--@return integer|nil bytes Conservative cumulative byte count.
local function conservative_public_bytes(value, state)
    state = state or { seen = {}, nodes = 0, bytes = 0 }
    local kind = type(value)
    local amount
    if kind == "string" then amount = #value + 16
    elseif kind == "boolean" then amount = 8
    elseif kind == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
    then
        amount = 32
    elseif kind ~= "table" then
        return nil
    else
        if state.seen[value] then return nil end
        state.seen[value] = true
        state.nodes = state.nodes + 1
        if state.nodes > 8192 then return nil end
        state.bytes = state.bytes + 16
        for key, item in pairs(value) do
            if type(key) ~= "string" and math.type(key) ~= "integer" then
                return nil
            end
            if conservative_public_bytes(key, state) == nil
                or conservative_public_bytes(item, state) == nil
            then
                return nil
            end
        end
        state.seen[value] = nil
        return state.bytes <= 262144 and state.bytes or nil
    end
    state.bytes = state.bytes + amount
    return state.bytes <= 262144 and state.bytes or nil
end

---Copies one Model definition into plain data for stale-preview checks.
--@param model table Candidate ConfigGeneration Model definition.
--@return table|nil snapshot Detached plain Model definition.
local function model_definition_snapshot(model)
    local copied, copied_ok = copy_plain(model)
    if not copied_ok then return nil end
    return copied
end

---Copies non-secret environment policy relevant to Model switch preflight.
--@param generation table Current ConfigGeneration.
--@param permission_name string Selected Permission name.
--@return table|nil snapshot Detached general, network, and Permission fields.
local function model_preflight_environment_snapshot(generation, permission_name)
    if type(generation) ~= "table"
        or type(generation.general) ~= "table"
        or type(generation.network) ~= "table"
        or type(generation.permissions) ~= "table"
        or type(generation.permissions[permission_name]) ~= "table"
    then
        return nil
    end
    local copied, copied_ok = copy_plain({
        general = generation.general,
        network = generation.network,
        permission_name = permission_name,
        permission = generation.permissions[permission_name],
    })
    if not copied_ok then return nil end
    return copied
end

---Classifies configured proxy disclosure without exposing secret proxy URLs.
--@param generation table Current ConfigGeneration.
--@return string policy Off, explicit secret slot, or public URL.
local function proxy_policy(generation)
    local network = type(generation.network) == "table" and generation.network or {}
    if network.follow_proxy ~= true then return "off" end
    if network.proxy_url_configured == true then return "explicit-secret-slot" end
    if type(network.proxy_url) == "string" and network.proxy_url ~= "" then
        return "explicit-public-url"
    end
    return "off"
end

---Projects one enabled main Model into compatibility and disclosure facts.
--@param generation table Current ConfigGeneration.
--@param name string Canonical Model name.
--@param model table Selected Model definition.
--@return table|nil summary Public protocol, endpoint, limits, and policy facts.
local function model_public_summary(generation, name, model)
    local endpoint = normalized_endpoint_identity(model.endpoint)
    if not endpoint then return nil end
    local protocol = model.protocol
    local auth_mode = protocol == "openai-chat" and "bearer"
        or protocol == "anthropic-messages" and "x-api-key" or nil
    if not auth_mode then return nil end
    local output_tokens = model.max_output_tokens or 4096
    local selected_proxy_policy = proxy_policy(generation)
    local selected_proxy_route = ""
    if selected_proxy_policy ~= "off" then
        selected_proxy_route = generation.network.proxy_route
        if type(selected_proxy_route) ~= "string" or selected_proxy_route == "" then
            return nil
        end
    end
    if model.enabled ~= true or model.tools_enabled ~= true
        or type(model.remote_model) ~= "string" or model.remote_model == ""
        or not valid_integer(model.context_length, 1)
        or not valid_integer(output_tokens, 1)
        or type(model.system_prompt) ~= "string"
        or (model.streaming ~= "force"
            and model.streaming ~= "try"
            and model.streaming ~= "off")
    then
        return nil
    end
    return {
        name = name,
        protocol = protocol,
        endpoint = model.endpoint,
        endpoint_origin = endpoint.origin,
        endpoint_route = endpoint.route,
        endpoint_identity = endpoint.identity,
        remote_model = model.remote_model,
        credential_policy = model.key_configured == true
            and (auth_mode .. ":Model." .. name .. ".Key")
            or (auth_mode .. ":none"),
        proxy_policy = selected_proxy_policy,
        proxy_route = selected_proxy_route,
        context_length = model.context_length,
        max_output_tokens = output_tokens,
        streaming = model.streaming,
        tools = "native",
        controls = "yaca-native-v1",
        roles = protocol .. "-canonical-v1",
    }
end

---Removes endpoint query values from a user-facing Model summary.
--@param summary table Internal Model compatibility summary.
--@param flags table|nil Current/default status flags.
--@return table disclosure Read-only Model summary safe for display.
local function model_disclosure_summary(summary, flags)
    local endpoint_path = summary.endpoint_route:match("^([^?]*)") or "/"
    local result = {
        name = summary.name,
        protocol = summary.protocol,
        endpoint_origin = summary.endpoint_origin,
        endpoint_path = endpoint_path,
        endpoint_query_configured = summary.endpoint_route:find("?", 1, true)
            ~= nil,
        remote_model = summary.remote_model,
        credential_policy = summary.credential_policy,
        proxy_policy = summary.proxy_policy,
        proxy_route = summary.proxy_route,
        context_length = summary.context_length,
        max_output_tokens = summary.max_output_tokens,
        streaming = summary.streaming,
        tools = summary.tools,
        controls = summary.controls,
        roles = summary.roles,
    }
    if flags then
        result.current = flags.current == true
        result.default = flags.default == true
    end
    return readonly(result, "Model disclosure summary")
end

---Lists bounded enabled main Models with current/default annotations.
--@param generation table Current ConfigGeneration.
--@param current_model string Selected Model name.
--@return table|nil catalog Read-only Model rows and truncation counts.
--@return table|nil err Structured missing-catalog failure.
local function model_catalog(generation, current_model)
    if type(generation) ~= "table" or type(generation.models) ~= "table"
        or type(generation.model_order) ~= "table"
    then
        return nil, failure(
            "ModelCatalogUnavailable",
            "the enabled Model catalog is unavailable"
        )
    end
    local rows = {}
    local total = 0
    for _, name in ipairs(generation.model_order) do
        local model = generation.models[name]
        if type(model) == "table" and model.enabled == true
            and model.tools_enabled == true
        then
            local summary = model_public_summary(generation, name, model)
            if summary then
                total = total + 1
                if #rows < MODEL_SELECTION_LIST_LIMIT then
                    rows[#rows + 1] = model_disclosure_summary(summary, {
                        current = name == current_model,
                        default = name == generation.default_model,
                    })
                end
            end
        end
    end
    if total == 0 then
        return nil, failure(
            "ModelCatalogUnavailable",
            "no enabled main Model is available"
        )
    end
    return readonly({
        current = current_model,
        rows = readonly(rows, "bounded Model catalog rows"),
        total = total,
        shown = #rows,
        truncated = total > #rows,
    }, "bounded Model catalog")
end

---Checks target Model compatibility and disclosure before any selection change.
--@param specification table Current/target Model, Prompt, view, and generation facts.
--@return table|nil preview Read-only compatibility and confirmation reasons.
--@return table|nil err Structured incompatible or stale-snapshot failure.
local function model_switch_preview(specification)
    local generation = specification.generation
    local current_name = specification.current_model
    local target_name = specification.target_model
    if type(generation) ~= "table" or type(generation.models) ~= "table"
        or type(generation.permissions) ~= "table"
        or type(current_name) ~= "string" or current_name == ""
        or type(target_name) ~= "string" or target_name == ""
        or type(specification.permission) ~= "string"
        or type(specification.context_prompt) ~= "string"
        or type(specification.prompt) ~= "table"
        or type(specification.prompt.assemble) ~= "function"
        or type(specification.tool_registry) ~= "table"
        or (specification.view ~= false and type(specification.view) ~= "table")
        or (specification.effective_at ~= "first-turn"
            and specification.effective_at ~= "next-turn")
        or (specification.transition_sequence ~= nil
            and not valid_integer(specification.transition_sequence, 1))
    then
        return nil, failure(
            "ModelPreflightUnavailable",
            "Model selection preflight inputs are incomplete"
        )
    end
    local current = generation.models[current_name]
    local target = generation.models[target_name]
    if type(target) ~= "table" then
        return nil, failure("ModelNotFound", "the exact Model selector was not found")
    end
    local current_summary = type(current) == "table"
        and model_public_summary(generation, current_name, current) or nil
    local target_summary = model_public_summary(generation, target_name, target)
    if not target_summary then
        return nil, failure(
            "ModelIncompatible",
            "the selected Model is not enabled for native tools and typed controls"
        )
    end
    if current_name == target_name then
        return readonly({
            kind = "model-switch-preview",
            unchanged = true,
            confirmation_required = false,
            effective_at = specification.effective_at,
            from = model_disclosure_summary(target_summary),
            to = model_disclosure_summary(target_summary),
            reasons = readonly({}, "Model confirmation reasons"),
        }, "unchanged Model selection preview")
    end
    if not current_summary then
        return nil, failure(
            "ModelPreflightUnavailable",
            "the current Model definition is unavailable"
        )
    end
    local permission = generation.permissions[specification.permission]
    if type(generation.general) ~= "table"
        or type(generation.general.system_prompt) ~= "string"
        or type(permission) ~= "table"
        or type(permission.system_prompt) ~= "string"
    then
        return nil, failure(
            "ModelPreflightUnavailable",
            "the current Prompt authority layers are unavailable"
        )
    end
    local bundle, bundle_error = specification.prompt:assemble({
        purpose = "main",
        config_generation = generation.id,
        layers = {
            global = {
                source = "General.SystemPrompt",
                version = generation.id,
                text = generation.general.system_prompt,
            },
            model = {
                source = "Model." .. target_name .. ".SystemPrompt",
                version = generation.id,
                text = target.system_prompt,
            },
            permission = {
                source = "Permission." .. specification.permission
                    .. ".SystemPrompt",
                version = generation.id,
                text = permission.system_prompt,
            },
            context = {
                source = "ContextPrompt",
                version = generation.id,
                text = specification.context_prompt,
            },
        },
        input = { user_message = "" },
        tool_mode = "registered",
    })
    if not bundle then return nil, bundle_error end
    local control_schema = require("prompt").control_schema("main")
    local tool_bytes = conservative_public_bytes(specification.tool_registry)
    local control_bytes = conservative_public_bytes(control_schema)
    if not tool_bytes or not control_bytes then
        return nil, failure(
            "ModelPreflightUnavailable",
            "tool or control schema size cannot be bounded"
        )
    end
    local view = specification.view
    local view_bytes = 0
    local history = {
        first_sequence = 0,
        last_sequence = 0,
        manifest_digest = false,
        body_bytes = 0,
        transition_last_sequence = 0,
    }
    if view ~= false then
        if type(view.digest) ~= "string" or view.digest == ""
            or not valid_integer(view.first_sequence, 0)
            or not valid_integer(view.last_sequence, view.first_sequence)
            or type(view.body) ~= "string"
        then
            return nil, failure(
                "ModelPreflightUnavailable",
                "the active durable ModelView is unavailable"
            )
        end
        view_bytes = #view.body
        history = {
            first_sequence = view.first_sequence,
            last_sequence = view.last_sequence,
            manifest_digest = view.digest,
            body_bytes = view_bytes,
            transition_last_sequence = specification.transition_sequence
                or (view.last_sequence + 1),
        }
    end
    local transition_reserve = view == false
        and 0 or MODEL_SELECTION_TRANSITION_RESERVE
    local required_tokens = view_bytes + bundle.estimated_token_upper_bound
        + tool_bytes + control_bytes + target_summary.max_output_tokens
        + transition_reserve
    if required_tokens > target_summary.context_length then
        return nil, failure(
            "ModelIncompatible",
            "the selected Model window cannot carry the current durable view, Prompt, tools, controls, and output reserve",
            "run .compact or select a larger-window Model"
        )
    end

    local reasons, reason_set = {}, {}
    ---Adds one distinct Model-switch confirmation reason in stable order.
    --@param name string Disclosure or compatibility reason.
    --@return nil Updates the preview's reason list.
    local function reason(name)
        if not reason_set[name] then
            reason_set[name] = true
            reasons[#reasons + 1] = name
        end
    end
    if current_summary.endpoint_identity ~= target_summary.endpoint_identity then
        reason("endpoint-route")
    end
    if current_summary.credential_policy ~= target_summary.credential_policy then
        reason("credential-policy")
    end
    if current_summary.protocol ~= target_summary.protocol then reason("protocol") end
    if current_summary.remote_model ~= target_summary.remote_model then
        reason("usage-source")
    end
    if current.system_prompt ~= target.system_prompt then reason("model-prompt") end
    if not plain_equal(current.adapter_options or {}, target.adapter_options or {}) then
        reason("adapter-policy")
    end
    if target_summary.context_length < current_summary.context_length then
        reason("context-window-decrease")
    end
    if target_summary.max_output_tokens < current_summary.max_output_tokens then
        reason("output-limit-decrease")
    end
    if target_summary.streaming ~= current_summary.streaming then
        reason("streaming-policy")
    end
    if target_summary.endpoint_origin:sub(1, 7) == "http://"
        and current_summary.endpoint_identity ~= target_summary.endpoint_identity
    then
        reason("plaintext-http")
    end
    if view ~= false and view.last_sequence > 0
        and (reason_set["endpoint-route"]
            or reason_set["credential-policy"]
            or reason_set["protocol"]
            or reason_set["usage-source"])
    then
        reason("history-destination")
    end
    local frozen_reasons = freeze(reasons, {}, "Model confirmation reasons")
    local frozen_history = freeze(history, {}, "Model history disclosure")
    local preflight = freeze({
        compatible = true,
        view_tokens = view_bytes,
        prompt_tokens = bundle.estimated_token_upper_bound,
        tool_schema_tokens = tool_bytes,
        control_schema_tokens = control_bytes,
        transition_reserve_tokens = transition_reserve,
        maximum_output_tokens = target_summary.max_output_tokens,
        required_tokens = required_tokens,
        window_tokens = target_summary.context_length,
        tools = "native-compatible",
        controls = "typed-compatible",
        roles = "canonical-compatible",
    }, {}, "Model compatibility preflight")
    if not frozen_reasons or not frozen_history or not preflight then
        return nil, failure("ModelPreflightUnavailable", "Model preview could not be frozen")
    end
    return readonly({
        kind = "model-switch-preview",
        unchanged = false,
        confirmation_required = #reasons > 0,
        effective_at = specification.effective_at,
        from = model_disclosure_summary(current_summary),
        to = model_disclosure_summary(target_summary),
        reasons = frozen_reasons,
        history = frozen_history,
        preflight = preflight,
    }, "Model selection preview")
end

---Adds the selection effective time to a detached Model status record.
--@param status table Draft or Session status fields.
--@param effective_at string First or next turn effective time.
--@return table projection Read-only Model selection status.
local function model_status_projection(status, effective_at)
    local values = {}
    for key, value in pairs(status) do values[key] = value end
    values.effective_at = effective_at
    return readonly(values, "Model selection status")
end

---Owns Model previews and one-time application for an unsaved draft.
--@param draft table Mutable draft Session facade.
--@param contexts table Prompt and Tool registry services.
--@return table|nil owner Read-only draft Model selection facade.
--@return table|nil err Structured missing-port failure.
local function new_draft_model_selection(draft, contexts)
    if type(draft) ~= "table" or type(draft.status) ~= "function"
        or type(draft.update) ~= "function"
        or type(draft.config_generation) ~= "function"
        or type(contexts) ~= "table" or type(contexts.prompt) ~= "table"
        or type(contexts.tool_registry) ~= "table"
    then
        return nil, failure(
            "InvalidModelSelection",
            "unsaved Model selection ports are incomplete"
        )
    end
    local generation = draft.config_generation()
    --@metatable bindings Associates control previews with the private operation facts used to reject stale admission.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local bindings = setmetatable({}, { __mode = "k" })
    local owner = {}

    ---Lists main Models compatible with the draft's ConfigGeneration.
    --@param self table Draft Model selection owner.
    --@return table|nil catalog Bounded Model catalog.
    --@return table|nil err Structured catalog failure.
    function owner:list()
        local status = draft.status()
        return model_catalog(generation, status.model)
    end

    ---Builds a bound first-turn Model-switch preview for the unsaved draft.
    --@param self table Draft Model selection owner.
    --@param selector string User Model selector.
    --@return table|nil preview Immutable compatibility preview.
    --@return table|nil err Structured missing or incompatible Model failure.
    function owner:preview(selector)
        local resolved = require("config").resolve_resource(generation, "Model", selector)
        if not resolved then return nil, failure("ModelNotFound", "the Model selector was not found") end
        selector = resolved
        local status = draft.status()
        local preview, preview_error = model_switch_preview({
            generation = generation,
            current_model = status.model,
            target_model = selector,
            permission = status.permission,
            context_prompt = status.context_prompt or "",
            prompt = contexts.prompt,
            tool_registry = contexts.tool_registry,
            view = false,
            effective_at = "first-turn",
        })
        if not preview then return nil, preview_error end
        local definition = generation.models[selector]
        local definition_snapshot = model_definition_snapshot(definition)
        if not definition_snapshot then
            return nil, failure(
                "ModelPreflightUnavailable",
                "the selected Model definition cannot be bound"
            )
        end
        bindings[preview] = {
            from = status.model,
            target = selector,
            definition = definition_snapshot,
            consumed = false,
        }
        return preview
    end

    ---Applies a still-current draft Model preview exactly once.
    --@param self table Draft Model selection owner.
    --@param preview table Preview issued by this owner.
    --@return table|nil status Updated first-turn Model status.
    --@return table|nil err Structured stale or update failure.
    function owner:apply(preview)
        local binding = bindings[preview]
        local status = draft.status()
        if not binding or binding.consumed or status.model ~= binding.from
            or not plain_equal(
                model_definition_snapshot(generation.models[binding.target]),
                binding.definition
            )
        then
            return nil, failure(
                "ModelSelectionStale",
                "the unsaved Model selection preview is stale"
            )
        end
        local updated, update_error = draft.update({ model = binding.target })
        if not updated then return nil, update_error end
        binding.consumed = true
        return model_status_projection(updated, "first-turn")
    end

    return readonly(owner, "unsaved Model selection owner")
end

---Composes the production Agent over either a newly published first turn or a
-- verified, quiescent existing Context. No Model request or Tool effect is
-- reachable before the relevant durable writer and Runtime bindings succeed.
-- Every later main turn reloads the complete Config and atomically replaces
-- its generation-bound Model/Tool/review ports while all are idle.
--@param composed table Production runtime and Context services.
--@param chat table New or continued Session bootstrap result.
--@param message string First user input text.
--@param source string First input source identity.
--@param first_lane string|nil Main or no-tool Ask first lane.
--@return table|nil agent Composed durable Agent and activity owners.
--@return table|nil err Structured publication, snapshot, or port failure.
function M.start_published_agent(composed, chat, message, source, first_lane)
    local continuing = type(chat) == "table" and chat.kind == "continue-chat"
    first_lane = first_lane or "main"
    local first_ask = not continuing and first_lane == "ask"
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
        or type(composed.publication.resolve_view) ~= "function"
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
        or (first_lane ~= "main" and first_lane ~= "ask")
        or (first_ask and type(chat.draft.begin_ask) ~= "function")
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
    local continued_workspace_key = continuing and workspace_identity_key(
        chat.workspace_identity
    ) or nil
    ---Rechecks the bound Workspace object before and after Context handoffs.
    --@param none No arguments.
    --@return boolean|nil valid True while the Workspace identity remains exact.
    --@return table|nil err Structured replaced-Workspace failure.
    local function verify_continued_workspace()
        if not continuing then return true end
        if not continued_workspace_key or chat.workspace_identity.kind ~= "directory" then
            return nil, failure(
                "InvalidAgentComposition", "the continued workspace identity is missing"
            )
        end
        local inspected, workspace = composed.backend.filesystem.direct_inspect(status.workspace)
        if not inspected then return nil, workspace end
        if workspace_identity_key(workspace.identity) ~= continued_workspace_key then
            return nil, failure("ContextTargetChanged", "the confirmed workspace was replaced")
        end
        return true
    end
    if continuing then
        local verified, verify_error = verify_continued_workspace()
        if not verified then chat.draft.close(); return nil, verify_error end
        receipt = chat.draft.open_receipt()
        if type(receipt) ~= "table"
            or receipt.durable ~= true
            or receipt.auto_continue ~= true
            or not valid_integer(receipt.generation, 1)
            or not valid_integer(receipt.event_count, 0)
            or receipt.last_sequence ~= receipt.event_count
            or type(receipt.runtime_initial_serials) ~= "table"
            or not valid_integer(receipt.approval_initial_serial, 0)
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
        local begin = first_ask and chat.draft.begin_ask or chat.draft.begin_main
        receipt, publication_error = begin(message, source)
        if not receipt then return nil, publication_error end
        local handoff_error
        handoff, handoff_error = chat.draft.agent_handoff()
        if not handoff then
            chat.draft.close()
            return nil, handoff_error
        end
        initial_snapshot = handoff.input
    end

    -- A new draft has no Context hash until begin_main publishes its XML.
    -- Bind every activity, including later main/ask turns, to that published
    -- identity instead of retaining the pre-publication status snapshot.
    status = chat.draft.status()

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
        workspace_identity = continued_workspace_key,
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
    local verified, verify_error = verify_continued_workspace()
    if not verified then chat.draft.close(); return nil, verify_error end
    local catalog = new_turn_catalog(first_ports)
    local ask_catalog = new_ask_catalog()
    local durable_settings_generation = generation

    ---Reloads current Config and captures a new turn from durable Session facts.
    --@param specification table Turn kind, user text, source, and Context generation.
    --@return table|nil generation Current ConfigGeneration.
    --@return table|nil snapshot Captured immutable turn snapshot.
    --@return table|nil err Structured stale or Config failure.
    local function reload_turn_snapshot(specification)
        local workspace_valid, workspace_error = verify_continued_workspace()
        if not workspace_valid then return nil, nil, workspace_error end
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
        workspace_valid, workspace_error = verify_continued_workspace()
        if not workspace_valid then return nil, nil, workspace_error end
        return next_generation, snapshot
    end

    local snapshots = readonly({
        ---Captures a fresh turn and stages its generation-bound activity ports.
        --@param specification table Requested turn kind and exact Context observation.
        --@return table|nil snapshot Immutable turn configuration snapshot.
        --@return table|nil err Structured stale or port-construction failure.
        capture = function(specification)
            if type(specification) ~= "table"
                or (specification.kind ~= "main" and specification.kind ~= "ask")
            then
                return nil, failure(
                    "InvalidTurnSnapshot",
                    "production snapshot catalog accepts only main or ask turns"
                )
            end
            if specification.kind == "main" and not catalog.idle() then
                return nil, failure(
                    "TurnActivitiesBusy",
                    "a later turn cannot replace active generation ports"
                )
            end
            if specification.kind == "ask" and not ask_catalog.idle() then
                return nil, failure(
                    "AskActivityBusy",
                    "a ask turn cannot replace an active ask generation"
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
                local candidate, candidate_error = build_ask_activity(composed, {
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
                local prepared, prepare_error = ask_catalog.prepare(candidate)
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
    if continuing or first_ask then
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
        ask = ask_catalog,
        views = readonly({
            prepare = composed.publication.prepare_view,
        }, "active durable Model view publication"),
    }, loop_options)
    if not loop then chat.draft.close(); return nil, loop_error end
    ---Closes a partially composed AgentLoop and draft after construction fails.
    --@param agent_error table Original structured composition failure.
    --@return nil No Agent is returned.
    --@return table err Original failure after best-effort cleanup.
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

    ---Projects effective durable Session settings and update timing.
    --@param active_generation table Current validated ConfigGeneration.
    --@param overrides table Durable Context Session override values.
    --@param context_generation integer Current Context generation.
    --@param effective_at string Current or next-turn application time.
    --@return table status Read-only Session settings projection.
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

    ---Binds a Session update to a live Runtime and exact Context generation.
    --@param none No arguments.
    --@return table|nil status Current Runtime status.
    --@return table context_or_error Durable turn Context or structured failure.
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

    ---Returns effective Session settings under a fresh durable observation.
    --@param self table Session settings owner.
    --@return table|nil status Read-only settings projection.
    --@return table|nil err Structured observation failure.
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

    ---Checks editor bytes against the current durable settings' private registry.
    -- Only non-secret hit descriptors leave the ConfigGeneration owner.
    ---Checks bytes against the current ConfigGeneration secret registry.
    --@param bytes string Candidate exported or displayed text.
    --@return boolean|nil safe Whether no registered secret was found.
    --@return table|nil err Structured secret-scan failure.
    function session_settings.scan_registered_secrets(bytes)
        return durable_settings_generation.scan_registered_secrets(bytes)
    end

    ---Publishes one typed Session override and adopts its exact Runtime receipt.
    --@param self table Session settings owner.
    --@param change table Override name, value, and update mode.
    --@return table|nil status New effective settings projection.
    --@return table|nil err Structured stale, publication, or durability failure.
    function session_settings:update(change)
        if type(change) ~= "table" then
            return nil, failure(
                "InvalidSessionUpdate",
                "a typed Session setting change is required"
            )
        end
        local allowed = {
            name = true,
            value = true,
            mode = true,
            expected_model = true,
            expected_model_environment = true,
            expected_model_generation = true,
        }
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
        if change.name == "CurrentModel" then
            if change.mode ~= nil
                or type(change.value) ~= "string" or change.value == ""
                or type(change.expected_model) ~= "table"
                or type(change.expected_model_environment) ~= "table"
                or type(change.expected_model_generation) ~= "table"
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "CurrentModel requires one bound target definition"
                )
            end
            next_overrides.CurrentModel = change.value
        elseif change.name == "CurrentPermission"
            or change.name == "DoubleCheckOverride"
            or change.name == "ContextPrompt"
        then
            if change.mode ~= nil or change.expected_model ~= nil
                or change.expected_model_environment ~= nil
                or change.expected_model_generation ~= nil
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "this Session setting does not accept extra binding metadata"
                )
            end
            next_overrides[change.name] = change.value
        elseif change.name == "DoubleCheckGoalOverride" then
            if change.expected_model ~= nil
                or change.expected_model_environment ~= nil
                or change.expected_model_generation ~= nil
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "DoubleCheck goal does not accept Model binding metadata"
                )
            end
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
        if change.name == "CurrentModel"
            and (not plain_equal(
                    model_definition_snapshot(next_generation.models[change.value]),
                    change.expected_model
                )
                or not plain_equal(
                    model_preflight_environment_snapshot(
                        next_generation,
                        next_generation.current_permission
                    ),
                    change.expected_model_environment
                )
                or type(next_generation.matches_model_secrets) ~= "function"
                or next_generation.matches_model_secrets(
                    change.expected_model_generation,
                    change.value
                ) ~= true)
        then
            return nil, failure(
                "ModelSelectionStale",
                "the selected Model definition, credentials, or Prompt environment "
                    .. "changed during Config reload"
            )
        end
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
    --@metatable model_bindings Associates model request previews with their private model, configuration and request bindings.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local model_bindings = setmetatable({}, { __mode = "k" })
    local model_selection = {}

    ---Binds Model selection to current Config, Session, Runtime, and view facts.
    --@param none No arguments.
    --@return table|nil status Current Runtime status.
    --@return table|nil context Durable Session and Context state.
    --@return table|nil err Structured binding mismatch.
    local function bound_model_observation()
        local runtime_status, turn_context = session_update_observation()
        if not runtime_status then return nil, nil, turn_context end
        local overrides = turn_context.overrides
        if type(overrides) ~= "table"
            or durable_settings_generation.current_model
                ~= overrides.CurrentModel
            or durable_settings_generation.current_permission
                ~= overrides.CurrentPermission
            or (durable_settings_generation.context_prompt or "")
                ~= (overrides.ContextPrompt or "")
            or type(runtime_status.active_view_manifest_ref) ~= "string"
            or runtime_status.active_view_manifest_ref == ""
            or not valid_integer(runtime_status.context_generation, 1)
            or not valid_integer(runtime_status.last_durable_sequence, 0)
        then
            return nil, nil, failure(
                "ModelPreflightUnavailable",
                "the active Config, Session, and ModelView bindings disagree"
            )
        end
        return runtime_status, turn_context
    end

    ---Lists enabled main Models under the current durable Session binding.
    --@param self table Model selection owner.
    --@return table|nil catalog Bounded Model catalog.
    --@return table|nil err Structured stale or unavailable binding.
    function model_selection:list()
        local runtime_status, turn_context, observation_error
            = bound_model_observation()
        if not runtime_status then return nil, observation_error end
        return model_catalog(
            durable_settings_generation,
            turn_context.overrides.CurrentModel
        )
    end

    ---Preflights one Model switch against the exact durable view and policy.
    --@param self table Model selection owner.
    --@param selector string User-selected Model name.
    --@return table|nil preview Bound compatibility and disclosure preview.
    --@return table|nil err Structured stale, missing, or incompatible Model.
    function model_selection:preview(selector)
        if type(selector) ~= "string" or selector == ""
            or selector:find("[%z\r\n]")
        then
            return nil, failure(
                "ModelNotFound",
                "an exact nonempty Model selector is required"
            )
        end
        local runtime_status, turn_context, observation_error
            = bound_model_observation()
        if not runtime_status then return nil, observation_error end
        if runtime_status.last_durable_sequence == math.maxinteger then
            return nil, failure(
                "ModelPreflightUnavailable",
                "the Context sequence space is exhausted"
            )
        end
        local view, view_error = composed.publication.resolve_view(
            runtime_status.active_view_manifest_ref
        )
        if not view then return nil, view_error end
        if type(view) ~= "table"
            or view.digest ~= runtime_status.active_view_manifest_ref
            or not valid_integer(view.first_sequence, 0)
            or not valid_integer(view.last_sequence, view.first_sequence)
            or view.last_sequence > runtime_status.last_durable_sequence
            or type(view.body) ~= "string"
        then
            return nil, failure(
                "ModelPreflightUnavailable",
                "the resolved durable ModelView does not bind the active Runtime"
            )
        end
        local generation = durable_settings_generation
        local resolved = require("config").resolve_resource(generation, "Model", selector)
        if not resolved then return nil, failure("ModelNotFound", "the Model selector was not found") end
        selector = resolved
        local preview, preview_error = model_switch_preview({
            generation = generation,
            current_model = turn_context.overrides.CurrentModel,
            target_model = selector,
            permission = turn_context.overrides.CurrentPermission,
            context_prompt = turn_context.overrides.ContextPrompt or "",
            prompt = contexts.prompt,
            tool_registry = contexts.tool_registry,
            view = view,
            transition_sequence = runtime_status.last_durable_sequence + 1,
            effective_at = "next-turn",
        })
        if not preview then return nil, preview_error end
        local definition = model_definition_snapshot(generation.models[selector])
        local environment = model_preflight_environment_snapshot(
            generation,
            turn_context.overrides.CurrentPermission
        )
        if not definition or not environment then
            return nil, failure(
                "ModelPreflightUnavailable",
                "the selected Model definition and Prompt environment cannot be bound"
            )
        end
        model_bindings[preview] = {
            generation = generation,
            context_generation = runtime_status.context_generation,
            last_sequence = runtime_status.last_durable_sequence,
            manifest_digest = runtime_status.active_view_manifest_ref,
            from = turn_context.overrides.CurrentModel,
            permission = turn_context.overrides.CurrentPermission,
            context_prompt = turn_context.overrides.ContextPrompt or "",
            target = selector,
            definition = definition,
            environment = environment,
            unchanged = preview.unchanged == true,
            consumed = false,
        }
        return preview
    end

    ---Publishes a confirmed, still-current Model switch for a later turn.
    --@param self table Model selection owner.
    --@param preview table Private preview issued by this owner.
    --@return table|nil status Updated durable Model selection.
    --@return table|nil err Structured stale, publication, or durability failure.
    function model_selection:apply(preview)
        local binding = model_bindings[preview]
        local runtime_status, turn_context, observation_error
            = bound_model_observation()
        if not runtime_status then return nil, observation_error end
        local overrides = turn_context.overrides
        if not binding or binding.consumed
            or durable_settings_generation ~= binding.generation
            or runtime_status.context_generation ~= binding.context_generation
            or runtime_status.last_durable_sequence ~= binding.last_sequence
            or runtime_status.active_view_manifest_ref ~= binding.manifest_digest
            or overrides.CurrentModel ~= binding.from
            or overrides.CurrentPermission ~= binding.permission
            or (overrides.ContextPrompt or "") ~= binding.context_prompt
            or not plain_equal(
                model_definition_snapshot(
                    durable_settings_generation.models[binding.target]
                ),
                binding.definition
            )
            or not plain_equal(
                model_preflight_environment_snapshot(
                    durable_settings_generation,
                    binding.permission
                ),
                binding.environment
            )
        then
            return nil, failure(
                "ModelSelectionStale",
                "the saved Model selection preview is stale"
            )
        end
        if binding.unchanged then
            binding.consumed = true
            return settings_projection(
                durable_settings_generation,
                overrides,
                runtime_status.context_generation,
                "current"
            )
        end
        local updated, update_error = session_settings:update({
            name = "CurrentModel",
            value = binding.target,
            expected_model = binding.definition,
            expected_model_environment = binding.environment,
            expected_model_generation = binding.generation,
        })
        if not updated then return nil, update_error end
        binding.consumed = true
        return model_status_projection(updated, "next-turn")
    end

    model_selection = readonly(
        model_selection,
        "production Model selection owner"
    )
    local compaction_owner, compaction_error = new_production_compaction(
        composed,
        catalog,
        loop,
        clock
    )
    if not compaction_owner then return fail_after_loop(compaction_error) end
    local admission = false
    if not continuing and not first_ask then
        local admission_error
        admission, admission_error = loop:resume_published_main(handoff)
        if not admission then return fail_after_loop(admission_error) end
    end
    local driver, driver_error = runtime_module.new_agent_activity_driver({
        loop = loop,
        model = catalog.model,
        tools = catalog.tools,
        reviews = catalog.reviews,
        ask = ask_catalog,
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
        models = model_selection,
        settings = session_settings,
        compaction = compaction_owner,
        draft = chat.draft,
        approval_initial_serial = continuing and receipt.approval_initial_serial or 0,
        ---Revalidates the active Context before exposing its current status.
        --@param none No arguments.
        --@return table|nil status Fresh exact Context inspection.
        --@return table|nil err Structured stale-Context failure.
        context_status = function()
            local called, result, inspection_error = pcall(composed.publication.inspect_active)
            if not called or not result then
                loop:fail_context_observation()
                return nil, failure(
                    "ContextStale",
                    "the active Context is stale; execution has stopped",
                    called and inspection_error and inspection_error.code or "inspection-failed"
                )
            end
            return result
        end,
        generation = generation,
        current_generation = catalog.generation,
        current_ask_generation = ask_catalog.generation,
        capabilities = readonly({
            published_first_turn = not continuing and not first_ask,
            reopened_existing_context = continuing,
            model = true,
            tools = true,
            reviews = true,
            approvals = true,
            later_turn_snapshots = true,
            ask = true,
            model_selection = true,
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

---Validates bounded interactive polling, draft, and output limits.
--@param options table Candidate coordinator hard limits.
--@return table|nil options Normalized admitted limits.
--@return table|nil err Structured invalid-limit failure.
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

---Checks terminal, renderer, CLI, Session, and Agent coordinator ports.
--@param ports table Candidate interactive application dependencies.
--@return table|nil ports Admitted original port set.
--@return table|nil err Structured missing-port failure.
local function coordinator_ports(ports)
    if type(ports) ~= "table"
        or type(ports.terminal) ~= "table"
        or type(ports.clock) ~= "table"
        or type(ports.cli) ~= "table"
        or type(ports.view) ~= "table"
        or type(ports.chat) ~= "table"
        or type(ports.chat.draft) ~= "table"
        or type(ports.draft_models) ~= "table"
        or type(ports.draft_models.list) ~= "function"
        or type(ports.draft_models.preview) ~= "function"
        or type(ports.draft_models.apply) ~= "function"
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
            or type(ports.initial_agent.models) ~= "table"
            or type(ports.initial_agent.models.list) ~= "function"
            or type(ports.initial_agent.models.preview) ~= "function"
            or type(ports.initial_agent.models.apply) ~= "function"
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

---Calls an owned coordinator port method and normalizes exceptions.
--@param owner table Port owner object.
--@param method string Method name.
--@param code string Structured failure code.
--@param message string Failure summary.
--@param ... any Forwarded method arguments.
--@return any|nil result Port result.
--@return table|nil err Structured port failure.
local function coordinator_call(owner, method, code, message, ...)
    local called, result, result_error = pcall(owner[method], owner, ...)
    if not called then return nil, failure(code, message .. " raised an exception") end
    if result == nil then return nil, result_error or failure(code, message .. " failed") end
    return result, result_error
end

---Calls a standalone coordinator port function and normalizes exceptions.
--@param callable function Port operation.
--@param code string Structured failure code.
--@param message string Failure summary.
--@param ... any Forwarded function arguments.
--@return any|nil result Port result.
--@return table|nil err Structured port failure.
local function coordinator_function(callable, code, message, ...)
    local called, result, result_error = pcall(callable, ...)
    if not called then return nil, failure(code, message .. " raised an exception") end
    if result == nil then return nil, result_error or failure(code, message .. " failed") end
    return result, result_error
end

---Extracts a safe stable code from a coordinator diagnostic.
--@param value any Structured error or thrown value.
--@return string code Valid public diagnostic identifier.
local function coordinator_error_id(value)
    local code = type(value) == "table" and value.code or "InternalError"
    if type(code) ~= "string" or not code:match("^[A-Za-z][A-Za-z0-9]+$") then
        return "InternalError"
    end
    return code
end

---Trims leading and trailing whitespace from one command input line.
--@param value string Input line.
--@return string trimmed Command text without surrounding whitespace.
local function trim_coordinator_line(value)
    return value:match("^%s*(.-)%s*$")
end

---Creates the single-threaded application owner for one interactive chat.
-- Terminal observations, typed Agent actions, approvals, and renderer blocks
-- all pass through this owner.  It uses bounded polling and an injected idle
-- wait, never infers domain state from already-rendered output, and restores
-- the terminal on every returned path.
--@param ports table Terminal, clock, CLI, view, chat, and Agent factory ports.
--@param options table Fixed input, output, polling, wait, and close limits.
--@return table|nil coordinator Readonly coordinator with a run method.
--@return table|nil err Structured construction failure.
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
    local multiline = false
    local multiline_bytes = 0
    local draft_rejected = false
    local assistant_draft = ""
    local ask_draft = ""
    local ask_draft_id = false
    local ask_focus_id = false
    local last_now
    local prompt_needed = false
    local approval = false
    local approval_serial = 0
    local model_change = false
    local context_change = false
    local model_change_serial = 0
    local prompt_edit = false
    local prompt_edit_serial = 0
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

    ---Reads a monotonic tick shared by terminal and Agent activity handling.
    --@param none No arguments.
    --@return integer|nil now Current monotonic tick.
    --@return table|nil err Structured clock failure.
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

    ---Publishes one semantic transcript block through the renderer.
    --@param block table User-visible semantic block.
    --@return boolean|nil published True when renderer accepts it.
    --@return table|nil err Structured renderer failure.
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

    ---Displays a bounded diagnostic and retains its details for inspection.
    --@param value any Structured operation failure.
    --@return boolean|nil published Whether the diagnostic was rendered.
    --@return table|nil err Structured renderer failure.
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
        local next_action = type(value) == "table" and value.next_action or nil
        if type(next_action) ~= "string" or next_action == "" then
            next_action = false
        end
        diagnostics_by_id[diagnostic_id] = {
            id = diagnostic_id,
            code = code,
            message = safe_diagnostic(message, 4096),
            suggestion = suggestion and safe_diagnostic(suggestion, 1024) or false,
            next_action = next_action
                and safe_diagnostic(next_action, 1024) or false,
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

    ---Displays one status message without changing domain state.
    --@param message string User-visible status text.
    --@return boolean|nil published Whether the status was rendered.
    --@return table|nil err Structured renderer failure.
    local function publish_status(message)
        return publish({ kind = "status", text = message })
    end

    ---Closes an active Prompt draft and preserves its cancellation reason.
    --@param reason string Prompt editor cancellation reason.
    --@return boolean|nil cancelled Whether edit state was cleared.
    --@return table|nil err Structured renderer or draft failure.
    local function cancel_prompt_edit(reason)
        if not prompt_edit then return true end
        local id = prompt_edit.id
        prompt_edit = false
        input_draft = ""
        prompt_needed = true
        return publish({ kind = "action", id = id, text = "not saved; " .. reason })
    end

    ---Renders the next input prompt for the current main or Ask focus.
    --@param focus string|nil Prompt focus override.
    --@return boolean|nil shown Whether the prompt was rendered.
    --@return table|nil err Structured renderer failure.
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

    ---Assigns a short display ID to a canonical durable Tool call.
    --@param canonical_id string Durable Tool call identity.
    --@return string display_id Stable display label for this chat.
    local function tool_display_id(canonical_id)
        local display_id = tool_ids[canonical_id]
        if display_id then return display_id end
        tool_serial = tool_serial + 1
        display_id = "tool-" .. tostring(tool_serial)
        tool_ids[canonical_id] = display_id
        return display_id
    end

    ---Publishes buffered main Model text as one transcript block.
    --@param none No arguments.
    --@return boolean|nil flushed Whether the buffer was rendered or empty.
    --@return table|nil err Structured renderer failure.
    local function flush_assistant()
        if assistant_draft == "" then return true end
        local value = assistant_draft
        assistant_draft = ""
        return publish({ kind = "assistant", text = value })
    end

    ---Adds a bounded main Model text delta to the visible response buffer.
    --@param value string New assistant text delta.
    --@return boolean|nil appended Whether the delta was retained.
    --@return table|nil err Structured output-limit or renderer failure.
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

    ---Publishes buffered no-tool Ask text for the matching Ask turn.
    --@param ask_id string Active Ask identity.
    --@return boolean|nil flushed Whether Ask text was rendered or empty.
    --@return table|nil err Structured renderer failure.
    local function flush_ask(ask_id)
        if ask_draft == "" then
            ask_draft_id = false
            return true
        end
        if type(ask_id) ~= "string" or ask_id == "" or ask_id ~= ask_draft_id then
            return nil, failure(
                "AskActivityContract",
                "ask transcript identity changed while streaming"
            )
        end
        local value = ask_draft
        ask_draft = ""
        ask_draft_id = false
        return publish({ kind = "ask", id = ask_id, text = value })
    end

    ---Adds a bounded Ask Model delta without merging it into main text.
    --@param ask_id string Active Ask identity.
    --@param value string New Ask text delta.
    --@return boolean|nil appended Whether the delta was retained.
    --@return table|nil err Structured output-limit or renderer failure.
    local function append_ask(ask_id, value)
        if type(ask_id) ~= "string" or ask_id == ""
            or type(value) ~= "string"
            or (ask_draft_id ~= false and ask_draft_id ~= ask_id)
            or #ask_draft + #value > admitted.maximum_assistant_bytes
        then
            return nil, failure(
                "CoordinatorOutputLimit",
                "ask transcript exceeds its fixed byte limit or binding"
            )
        end
        ask_draft_id = ask_id
        ask_draft = ask_draft .. value
        return true
    end

    ---Projects one no-tool Ask Model event into the separate Ask transcript.
    --@param ask_id string Active Ask turn identity.
    --@param event table Canonical Ask Model event.
    --@return boolean|nil projected Whether the event was handled.
    --@return table|nil err Structured invalid-event or renderer failure.
    local function project_ask_model_event(ask_id, event)
        if type(event) ~= "table" or type(event.kind) ~= "string" then
            return nil, failure(
                "AskActivityContract",
                "interactive ask Model event is invalid"
            )
        end
        if event.kind == "response_start"
            or event.kind == "usage_update"
            or event.kind == "reasoning_summary_delta"
            or event.kind == "tool_arguments_delta"
        then
            return true
        end
        if event.kind == "text_delta" then return append_ask(ask_id, event.text) end
        if event.kind == "response_finish" then return flush_ask(ask_id) end
        if event.kind == "tool_call_start"
            or event.kind == "tool_call_complete"
            or event.kind == "control"
        then
            local flushed, flush_error = flush_ask(ask_id)
            if not flushed then return nil, flush_error end
            return publish_error({
                code = "InvalidAskResponse",
                message = "The Ask response attempted a Tool or control action; it was rejected.",
            })
        end
        if event.kind == "protocol_error" or event.kind == "transport_error" then
            local flushed, flush_error = flush_ask(ask_id)
            if not flushed then return nil, flush_error end
            return publish_error({
                code = "AskModelResponseError",
                message = "Ask Model response failed: " .. tostring(event.error_id),
            })
        end
        return nil, failure(
            "AskActivityContract",
            "interactive ask Model event kind is unknown"
        )
    end

    ---Projects a canonical main Model event into text, Tool, or notice blocks.
    --@param event table Canonical Model activity event.
    --@return boolean|nil projected Whether the event was handled.
    --@return table|nil err Structured invalid-event or renderer failure.
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
            local payload = type(event.payload) == "table" and event.payload or {}
            local statement = event.control == "finish" and payload.summary
                or event.control == "refuse" and payload.reason
            if type(statement) == "string" and statement ~= "" then
                local appended, append_error = append_assistant(statement)
                if not appended then return nil, append_error end
                flushed, flush_error = flush_assistant()
                if not flushed then return nil, flush_error end
            end
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

    ---Projects foreground Tool progress and terminal events by display ID.
    --@param event table Canonical Tool activity event.
    --@param active_tool_call_id string|nil Durable Tool call identity.
    --@return boolean|nil projected Whether the event was rendered.
    --@return table|nil err Structured invalid-event or renderer failure.
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

    ---Projects a typed AgentLoop transition after its durable reduction.
    --@param event table Driver transition with cause and typed result.
    --@return boolean|nil projected Whether the transition was displayed.
    --@return table|nil err Structured invalid-cause or renderer failure.
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
        if event.cause == "ask-response" then
            local flushed, flush_error = flush_ask(event.ask_id)
            if not flushed then return nil, flush_error end
            if ask_focus_id == event.ask_id then ask_focus_id = false end
            return publish_status(
                "Ask " .. tostring(event.ask_id)
                    .. " outcome: " .. tostring(result.outcome)
            )
        end
        return nil, failure(
            "AgentDriverFailure",
            "interactive Runtime transition cause is unknown"
        )
    end

    ---Renders a bounded driver event batch in causal order.
    --@param step table Agent activity driver step result.
    --@param before table AgentLoop status before the step.
    --@return boolean|nil projected True after every event is handled.
    --@return table|nil err Structured projection failure.
    local function project_driver_events(step, before)
        for _, event in ipairs(step.events) do
            local projected, projection_error
            if event.kind == "model-event" then
                projected, projection_error = project_model_event(event.event)
            elseif event.kind == "ask-model-event" then
                projected, projection_error = project_ask_model_event(
                    event.ask_id,
                    event.event
                )
            elseif event.kind == "tool-event" then
                projected, projection_error = project_tool_event(
                    event.event,
                    event.adapter_call_id or event.tool_call_id or before.active_tool_call_id
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

    ---Builds the exact user approval card for one pending Tool call.
    --@param action_id string Local approval display identity.
    --@param snapshot table Frozen Tool target, capabilities, and argument facts.
    --@return table lines Ordered approval details and one-shot choices.
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

    ---Prepares and displays a typed approval for the exact pending Tool call.
    --@param status table Current AgentLoop status.
    --@return boolean|nil ready True when no approval or a matching card is shown.
    --@return table|nil err Structured snapshot or renderer failure.
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
        if model_change then
            local expired_id = model_change.action_id
            model_change = false
            local expired, expired_error = publish({
                kind = "action",
                id = expired_id,
                text = "not applied; a Tool approval became pending",
            })
            if not expired then return nil, expired_error end
        end
        if prompt_edit then
            local cancelled, cancel_error = cancel_prompt_edit("a Tool approval became pending")
            if not cancelled then return nil, cancel_error end
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
        local initial_serial = agent.approval_initial_serial
        if initial_serial == nil then initial_serial = 0 end
        if not valid_integer(initial_serial, 0) then
            return nil, failure("ApprovalIdentityInvalid", "the approval identity waterline is invalid")
        end
        approval_serial = math.max(approval_serial, initial_serial)
        if approval_serial == math.maxinteger then
            return nil, failure("ApprovalIdentityExhausted", "the approval identity range is exhausted")
        end
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

    ---Displays a newly observed waiting or terminal Agent state once.
    --@param status table Current AgentLoop status.
    --@return boolean|nil projected Whether the state was handled.
    --@return table|nil err Structured renderer failure.
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
        if status.state == "WaitingUser" and status.pending_kind == "termination-review" then
            return publish({ kind = "notice", text =
                "Termination review has not accepted completion. "
                .. "Reply with clarification to continue, or use .cancel to stop this turn." })
        end
        if status.state == "WaitingUser" and status.pending_kind == "action-review" then
            return publish({ kind = "notice", text =
                "Action review is unresolved; the proposed tool has not run. "
                .. "Use .cancel to stop this turn, then revise the request or review Model settings." })
        end
        if status.state == "Idle" and status.last_outcome ~= false then
            return publish_status("Turn outcome: " .. tostring(status.last_outcome))
        end
        if status.state == "Closing" then return publish_status("Session closed.") end
        return true
    end

    ---Advances one Agent activity step and renders its typed events.
    --@param none No arguments.
    --@return boolean|nil progressed Whether the Agent changed or emitted output.
    --@return table|nil err Structured driver or projection failure.
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

    ---Extracts a typed compaction terminal outcome from its owner result.
    --@param result table|any Compaction owner result.
    --@return string|false outcome Terminal outcome or false while active.
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

    ---Resumes or blocks a deferred Agent request after compaction settles.
    --@param result table Compaction owner terminal result.
    --@return boolean|nil resolved True when no preflight or exact resolution succeeds.
    --@return table|nil err Structured mismatch or Runtime failure.
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

    ---Displays one typed compaction result and its durable settlement.
    --@param result table Compaction owner terminal result.
    --@return boolean|nil published Whether the outcome was rendered.
    --@return table|nil err Structured renderer or preflight failure.
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

    ---Polls the active compaction owner and projects its events.
    --@param none No arguments.
    --@return boolean|nil progressed Whether compaction emitted or changed state.
    --@return table|nil err Structured activity or renderer failure.
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

    ---Starts automatic compaction for a pending Model preflight when needed.
    --@param none No arguments.
    --@return boolean|nil progressed Whether preflight advanced.
    --@return table|nil err Structured compaction or Runtime failure.
    local function drive_automatic_preflight()
        if not agent or type(agent.compaction) ~= "table" then return false end
        local status = agent.loop:status()
        if status.compaction_preflight_state ~= "pending" then return false end
        if agent.compaction:status().active == true
            or status.ask_state ~= "idle"
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

    ---Builds the current user-facing Session and Agent status lines.
    --@param none No arguments.
    --@return table lines Ordered bounded status text.
    local function status_lines()
        local editing = prompt_edit and (prompt_edit.id .. " ("
            .. tostring(#prompt_edit.draft) .. " bytes; not saved)") or "none"
        if not agent then
            local status = admitted_ports.chat.draft.status()
            local lines = { "state: draft-ready", "prompt editor: " .. editing }
            for _, line in ipairs(session_status_lines(status)) do
                lines[#lines + 1] = line
            end
            lines[#lines + 1] = "context change: " .. (context_change and context_change.context_hash or "none")
            lines[#lines + 1] = "model change: "
                .. (model_change and tostring(model_change.action_id) or "none")
            return lines
        end
        local status = agent.loop:status()
        local compact_status = agent.compaction:status()
        local settings_called, settings_status = pcall(
            agent.settings.status,
            agent.settings
        )
        if not settings_called then settings_status = nil end
        local lines = {
            "state: " .. tostring(status.state),
            "prompt editor: " .. editing,
            "context change: " .. (context_change and context_change.context_hash or "none"),
            "turn: " .. tostring(status.turn_id),
            "model change: "
                .. (model_change and tostring(model_change.action_id) or "none"),
            "context generation: " .. tostring(status.context_generation),
            "pending: " .. tostring(status.pending_kind),
            "automatic preflight: "
                .. tostring(status.compaction_preflight_state)
                .. " " .. tostring(status.compaction_preflight_id),
            "queue: " .. tostring(status.queue_count)
                .. "/" .. tostring(status.queue_maximum),
            "ask: " .. tostring(status.ask_state)
                .. " " .. tostring(status.active_ask_id),
            "last outcome: " .. tostring(status.last_outcome),
            "compaction: " .. tostring(compact_status.state)
                .. " " .. tostring(compact_status.active_compaction_id),
            "compaction circuit: "
                .. tostring(compact_status.automatic_circuit_state)
                .. " failures="
                .. tostring(compact_status.automatic_failure_count),
        }
        local current = agent.draft.status()
        local context_error
        if type(agent.context_status) == "function" then
            local verified
            verified, context_error = coordinator_function(
                agent.context_status,
                "ContextStale",
                "active Context inspection"
            )
            if verified then
                current = {
                    workspace = current.workspace,
                    display_name = verified.display_name,
                    context_hash = verified.context_hash,
                }
            else
                deferred_failure = context_error
                lifecycle = "closing"
                lines[#lines + 1] = "fail-stop: " .. coordinator_error_id(context_error)
                    .. ": " .. safe_diagnostic(context_error.message, 512)
            end
        end
        local settings = type(settings_status) == "table" and settings_status or {}
        for _, line in ipairs(session_status_lines({
            workspace = current.workspace,
            display_name = current.display_name,
            context_hash = current.context_hash,
            stale = status.halted == true or context_error ~= nil,
            config_generation = settings.config_generation,
            model = settings.model,
            permission = settings.permission,
            double_check = settings.double_check_effective,
        })) do
            lines[#lines + 1] = line
        end
        return lines
    end

    ---Renders interactive help for one CLI topic.
    --@param topic string|nil Requested help topic.
    --@return boolean|nil shown Whether help was rendered.
    --@return table|nil err Structured renderer or help failure.
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

    ---Displays retained details for a previously shown diagnostic identity.
    --@param diagnostic_id string Local diagnostic display ID.
    --@return boolean|nil shown Whether details were rendered.
    --@return table|nil err Structured missing-detail or renderer failure.
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
        if model_change and diagnostic_id == model_change.action_id then
            return publish({
                kind = "details",
                id = model_change.action_id,
                lines = model_change.lines,
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
        if record.next_action then
            lines[#lines + 1] = "next action: " .. record.next_action
        end
        return publish({ kind = "details", id = record.id, lines = lines })
    end

    ---Normalizes one cautious-command scalar for bounded display.
    --@param value any Candidate command value.
    --@return string word Safe scalar text.
    local function cautious_word(value)
        if value == true then return "on" end
        if value == false then return "off" end
        return tostring(value)
    end

    ---Displays a cautious Session setting preview with its effective timing.
    --@param values table Proposed or current setting values.
    --@param suffix string|nil Additional status line.
    --@return boolean|nil published Whether the preview was rendered.
    --@return table|nil err Structured renderer failure.
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

    ---Reads the current durable Session settings from the active Agent.
    --@param none No arguments.
    --@return table|nil status Effective Session settings.
    --@return table|nil err Structured unavailable or stale Session failure.
    local function session_settings_status()
        if agent then
            return coordinator_call(
                agent.settings,
                "status",
                "SessionUpdateFailure",
                "saved Session settings status"
            )
        end
        return coordinator_function(
            admitted_ports.chat.draft.status,
            "SessionUpdateFailure",
            "unsaved Session settings status"
        )
    end

    ---Applies a typed cautious Session setting through its durable owner.
    --@param request table Parsed cautious command.
    --@return boolean|nil applied Whether the change was rendered.
    --@return table|nil err Structured validation or publication failure.
    local function apply_cautious(request)
        local current, status_error = session_settings_status()
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

    ---Displays the current or proposed Context Prompt with bounded lines.
    --@param values table Prompt setting fields.
    --@param suffix string|nil Additional status line.
    --@return boolean|nil published Whether the prompt summary was rendered.
    --@return table|nil err Structured renderer failure.
    local function publish_context_prompt(values, suffix)
        local prompt = values.context_prompt
        if type(prompt) ~= "string" then
            return nil, failure(
                "SessionUpdateFailure",
                "current ContextPrompt is unavailable"
            )
        end
        local quoted = prompt == "" and "| (empty)"
            or ("| " .. prompt:gsub("\n", "\n| "))
        local text = "bytes: " .. tostring(#prompt)
            .. "\neffective: " .. tostring(values.effective_at or "current")
            .. "\n" .. quoted
        if suffix then text = text .. "\n" .. suffix end
        return publish({
            kind = "details",
            id = "context-prompt",
            text = text,
        })
    end

    ---Applies a typed Context Prompt change through durable Session settings.
    --@param request table Parsed prompt command.
    --@return boolean|nil applied Whether the update was rendered.
    --@return table|nil err Structured validation or publication failure.
    local function apply_prompt(request)
        local current, status_error = session_settings_status()
        if not current then return nil, status_error end
        if request.operation == "show" then
            if request.text ~= nil then
                return nil, failure(
                    "InvalidSessionUpdate",
                    ".prompt show does not accept text"
                )
            end
            return publish_context_prompt(current)
        end
        if request.operation == "edit" then
            if request.text ~= nil then
                return nil, failure("InvalidSessionUpdate", ".prompt edit does not accept text")
            end
            if approval or model_change or prompt_edit then
                return nil, failure("PromptEditorBusy", "finish the pending interaction before editing Prompt")
            end
            local scan
            if agent then
                scan = agent.settings.scan_registered_secrets
            elseif type(admitted_ports.chat.draft.config_generation) == "function" then
                local generation = admitted_ports.chat.draft.config_generation()
                scan = generation and generation.scan_registered_secrets
            end
            if type(scan) ~= "function"
                or type(admitted_ports.cli.parse_prompt_editor) ~= "function"
            then
                return nil, failure("PromptEditorUnavailable", "Prompt editor validation is unavailable")
            end
            if type(current.context_prompt) ~= "string"
                or #current.context_prompt > admitted.maximum_draft_bytes
            then
                return nil, failure("DraftLimit", "current Prompt exceeds the editor byte limit")
            end
            if prompt_edit_serial == math.maxinteger then
                return nil, failure("PromptEditorLimit", "Prompt editor identity space is exhausted")
            end
            prompt_edit_serial = prompt_edit_serial + 1
            prompt_edit = {
                id = "prompt-edit-" .. tostring(prompt_edit_serial),
                original = current.context_prompt,
                draft = current.context_prompt,
                config_generation = current.config_generation,
                owner = agent or admitted_ports.chat.draft,
                scan = scan,
                has_lines = current.context_prompt ~= "",
            }
            return publish({
                kind = "action", id = prompt_edit.id,
                lines = {
                    "Editing ContextPrompt in memory; other text appends a line.",
                    "bytes: " .. tostring(#prompt_edit.draft) .. "/" .. tostring(admitted.maximum_draft_bytes),
                    ".show | .clear | .reset | .cancel | .save " .. prompt_edit.id,
                    "Use .. to start literal text with a dot; Esc cancels without saving.",
                    "The saved Prompt applies on the next turn.",
                },
            })
        end
        local value
        if request.operation == "set" then
            if type(request.text) ~= "string" or request.text == "" then
                return nil, failure(
                    "InvalidSessionUpdate",
                    ".prompt set requires nonempty text"
                )
            end
            value = request.text
        elseif request.operation == "clear" then
            if request.text ~= nil then
                return nil, failure(
                    "InvalidSessionUpdate",
                    ".prompt clear does not accept text"
                )
            end
            value = ""
        else
            return nil, failure(
                "InvalidSessionUpdate",
                "unknown ContextPrompt operation"
            )
        end
        if current.context_prompt == value then
            return publish_context_prompt(current)
        end
        local updated, update_error
        if agent then
            updated, update_error = coordinator_call(
                agent.settings,
                "update",
                "SessionUpdateFailure",
                "saved ContextPrompt update",
                { name = "ContextPrompt", value = value }
            )
        else
            updated, update_error = coordinator_function(
                admitted_ports.chat.draft.update,
                "SessionUpdateFailure",
                "unsaved ContextPrompt update",
                { context_prompt = value }
            )
        end
        if not updated then return nil, update_error end
        return publish_context_prompt(
            updated,
            agent and "The change applies on the next turn."
                or "The change applies when the first turn starts."
        )
    end

    ---Rejects a Prompt editor draft containing a registered Config secret.
    --@param value string Candidate in-memory Prompt text.
    --@return boolean|nil safe True when the draft contains no registered secret.
    --@return table|nil err Structured scan or secret failure.
    local function prompt_draft_safe(value)
        local hits, scan_error = coordinator_function(
            prompt_edit.scan, "PromptSecretScanFailure", "Prompt draft secret scan", value
        )
        if not hits then return nil, scan_error end
        if type(hits) ~= "table" then
            return nil, failure("PromptSecretScanFailure", "Prompt draft secret scan failed")
        end
        for _ in pairs(hits) do
            return nil, failure("RegisteredSecret", "Prompt draft contains a registered secret")
        end
        return true
    end

    -- Owns one bounded multi-line edit until exact save, cancel, or preemption.
    -- Draft content is never submitted to a main/ask/steer lane or persisted
    -- before save; publication continues to use the existing Session owner.
    --@param source string Raw Prompt editor input line.
    --@return boolean|nil handled Whether the edit command was handled.
    --@return table|nil err Structured draft or renderer failure.
    local function route_prompt_editor(source)
        local command, command_error = coordinator_function(
            admitted_ports.cli.parse_prompt_editor, "PromptEditorInput", "Prompt editor parsing",
            source, prompt_edit.id
        )
        if not command then return nil, command_error end
        if command.operation == "chat" then return false, nil, command.text end
        if command.operation == "cancel" then return cancel_prompt_edit("cancelled") end
        if command.operation == "save" then
            local current, status_error = session_settings_status()
            if not current then return nil, status_error end
            if prompt_edit.owner ~= (agent or admitted_ports.chat.draft)
                or current.context_prompt ~= prompt_edit.original
                or current.config_generation ~= prompt_edit.config_generation
            then
                return nil, failure("PromptEditorStale", "Session settings changed; cancel and reopen the editor")
            end
            local safe, scan_error = prompt_draft_safe(prompt_edit.draft)
            if not safe then return nil, scan_error end
            local request = { operation = "clear" }
            if prompt_edit.draft ~= "" then
                request = { operation = "set", text = prompt_edit.draft }
            end
            local saved, save_error = apply_prompt(request)
            if not saved then return nil, save_error end
            local id = prompt_edit.id
            prompt_edit = false
            return publish({ kind = "action", id = id, text = "saved" })
        end
        if command.operation == "show" then
            local safe, scan_error = prompt_draft_safe(prompt_edit.draft)
            if not safe then return nil, scan_error end
            return publish_context_prompt({ context_prompt = prompt_edit.draft, effective_at = "not saved" })
        end
        local value, has_lines
        if command.operation == "clear" then
            value, has_lines = "", false
        elseif command.operation == "reset" then
            value, has_lines = prompt_edit.original, prompt_edit.original ~= ""
        elseif command.operation == "append" then
            local separator = prompt_edit.has_lines and "\n" or ""
            if #prompt_edit.draft + #separator + #command.text > admitted.maximum_draft_bytes then
                return nil, failure("DraftLimit", "Prompt draft exceeds its byte limit; clear or cancel it")
            end
            value, has_lines = prompt_edit.draft .. separator .. command.text, true
        else
            return nil, failure("PromptEditorInput", "unknown Prompt editor operation")
        end
        local safe, scan_error = prompt_draft_safe(value)
        if not safe then return nil, scan_error end
        prompt_edit.draft, prompt_edit.has_lines = value, has_lines
        return publish_status("Prompt draft " .. prompt_edit.id .. ": " .. tostring(#value)
            .. "/" .. tostring(admitted.maximum_draft_bytes) .. " bytes; not saved.")
    end

    ---Returns the saved or unsaved Model selection owner for this chat.
    --@param none No arguments.
    --@return table owner Current Model selection facade.
    local function active_model_owner()
        return agent and agent.models or admitted_ports.draft_models
    end

    ---Validates and renders a bounded Model catalog without endpoint secrets.
    --@param result table Model picker catalog result.
    --@return boolean|nil published Whether catalog details were rendered.
    --@return table|nil err Structured contract or renderer failure.
    local function publish_model_catalog(result)
        if type(result) ~= "table" or type(result.rows) ~= "table"
            or type(result.current) ~= "string"
            or not valid_integer(result.total, 0)
            or not valid_integer(result.shown, 0)
            or result.shown ~= #result.rows
            or result.total < result.shown
            or result.shown > MODEL_SELECTION_LIST_LIMIT
            or type(result.truncated) ~= "boolean"
            or result.truncated ~= (result.total > result.shown)
        then
            return nil, failure(
                "ModelSelectionContract",
                "Model picker returned an invalid bounded catalog"
            )
        end
        local lines = {
            "current: " .. safe_diagnostic(result.current, 128),
        }
        for index, row in ipairs(result.rows) do
            if type(row) ~= "table"
                or type(row.name) ~= "string" or row.name == ""
                or type(row.protocol) ~= "string"
                or type(row.endpoint_origin) ~= "string"
                or type(row.endpoint_path) ~= "string"
                or type(row.endpoint_query_configured) ~= "boolean"
                or type(row.proxy_policy) ~= "string"
                or type(row.proxy_route) ~= "string"
                or type(row.remote_model) ~= "string"
                or type(row.credential_policy) ~= "string"
                or not valid_integer(row.context_length, 1)
                or not valid_integer(row.max_output_tokens, 1)
                or type(row.current) ~= "boolean"
                or type(row.default) ~= "boolean"
            then
                return nil, failure(
                    "ModelSelectionContract",
                    "Model picker returned an invalid catalog row"
                )
            end
            local flags = row.current and "current" or "available"
            if row.default then flags = flags .. ",default" end
            lines[#lines + 1] = string.format(
                "%2d %s [%s] %s/%s %s%s window=%d output=%d streaming=%s credential=%s",
                index,
                safe_diagnostic(row.name, 128),
                flags,
                safe_diagnostic(row.protocol, 64),
                safe_diagnostic(row.remote_model, 128),
                safe_diagnostic(row.endpoint_origin, 256),
                safe_diagnostic(row.endpoint_path, 256)
                    .. (row.endpoint_query_configured and "?configured" or ""),
                row.context_length,
                row.max_output_tokens,
                safe_diagnostic(tostring(row.streaming), 32),
                safe_diagnostic(row.credential_policy, 192)
            )
            lines[#lines + 1] = "   proxy: "
                .. safe_diagnostic(row.proxy_policy, 128)
                .. (row.proxy_route ~= "" and " "
                    .. safe_diagnostic(row.proxy_route, 512) or "")
        end
        if result.truncated then
            lines[#lines + 1] = "More enabled Models exist; the bounded list was truncated."
        end
        lines[#lines + 1] = "Use .model <exact-name> to select one Model."
        return publish({ kind = "details", id = "models", lines = lines })
    end

    ---Builds disclosure-safe lines for one before/after Model summary.
    --@param prefix string From or to display label.
    --@param summary table Public Model summary without query values.
    --@return table lines Ordered Model disclosure lines.
    local function model_summary_lines(prefix, summary)
        return {
            prefix .. " name: " .. safe_diagnostic(summary.name, 128),
            prefix .. " protocol/remote: "
                .. safe_diagnostic(summary.protocol, 64) .. "/"
                .. safe_diagnostic(summary.remote_model, 128),
            prefix .. " endpoint: "
                .. safe_diagnostic(summary.endpoint_origin, 256)
                .. safe_diagnostic(summary.endpoint_path, 256)
                .. (summary.endpoint_query_configured and "?configured" or ""),
            prefix .. " credential: "
                .. safe_diagnostic(summary.credential_policy, 192),
            prefix .. " proxy: " .. safe_diagnostic(summary.proxy_policy, 128)
                .. (summary.proxy_route ~= "" and " "
                    .. safe_diagnostic(summary.proxy_route, 512) or ""),
            prefix .. " window/output: " .. tostring(summary.context_length)
                .. "/" .. tostring(summary.max_output_tokens),
            prefix .. " streaming/tools/controls/roles: "
                .. safe_diagnostic(summary.streaming, 32) .. "/"
                .. safe_diagnostic(summary.tools, 32) .. "/"
                .. safe_diagnostic(summary.controls, 64) .. "/"
                .. safe_diagnostic(summary.roles, 64),
        }
    end

    ---Checks all public Model disclosure fields before rendering a preview.
    --@param summary any Candidate Model summary.
    --@return boolean valid Whether required public fields are present.
    local function valid_model_summary(summary)
        return type(summary) == "table"
            and type(summary.name) == "string" and summary.name ~= ""
            and type(summary.protocol) == "string"
            and type(summary.endpoint_origin) == "string"
            and type(summary.endpoint_path) == "string"
            and type(summary.endpoint_query_configured) == "boolean"
            and type(summary.remote_model) == "string"
            and type(summary.credential_policy) == "string"
            and type(summary.proxy_policy) == "string"
            and type(summary.proxy_route) == "string"
            and valid_integer(summary.context_length, 1)
            and valid_integer(summary.max_output_tokens, 1)
            and type(summary.streaming) == "string"
            and type(summary.tools) == "string"
            and type(summary.controls) == "string"
            and type(summary.roles) == "string"
    end

    ---Checks compatibility, history, and confirmation facts in a Model preview.
    --@param preview table Candidate saved or draft Model switch preview.
    --@return boolean|nil valid True when disclosure is coherent.
    --@return table|nil err Structured preview contract failure.
    local function validate_model_preview(preview)
        if type(preview) ~= "table"
            or preview.kind ~= "model-switch-preview"
            or type(preview.unchanged) ~= "boolean"
            or type(preview.confirmation_required) ~= "boolean"
            or (preview.effective_at ~= "first-turn"
                and preview.effective_at ~= "next-turn")
            or not valid_model_summary(preview.from)
            or not valid_model_summary(preview.to)
            or not dense_string_array(preview.reasons)
            or (preview.unchanged and preview.confirmation_required)
            or preview.unchanged ~= (preview.from.name == preview.to.name)
            or preview.confirmation_required ~= (#preview.reasons > 0)
        then
            return nil, failure(
                "ModelSelectionContract",
                "Model selection preview is incomplete"
            )
        end
        if not preview.unchanged then
            local history = preview.history
            local preflight = preview.preflight
            if type(history) ~= "table"
                or not valid_integer(history.first_sequence, 0)
                or not valid_integer(history.last_sequence, history.first_sequence)
                or not valid_integer(history.body_bytes, 0)
                or not valid_integer(history.transition_last_sequence, 0)
                or (preview.effective_at == "next-turn" and (
                    type(history.manifest_digest) ~= "string"
                    or history.manifest_digest == ""
                    or history.transition_last_sequence <= history.last_sequence
                ))
                or (preview.effective_at == "first-turn" and (
                    history.manifest_digest ~= false
                    or history.first_sequence ~= 0
                    or history.last_sequence ~= 0
                    or history.body_bytes ~= 0
                    or history.transition_last_sequence ~= 0
                ))
                or type(preflight) ~= "table"
                or preflight.compatible ~= true
                or not valid_integer(preflight.required_tokens, 0)
                or not valid_integer(preflight.window_tokens, 1)
                or preflight.required_tokens > preflight.window_tokens
            then
                return nil, failure(
                    "ModelSelectionContract",
                    "Model compatibility or history disclosure is incomplete"
                )
            end
        end
        return true
    end

    ---Displays the effective Model after a preview is applied or unchanged.
    --@param updated table Model selection status.
    --@param unchanged boolean Whether the selected Model remained the same.
    --@return boolean|nil published Whether the result was rendered.
    --@return table|nil err Structured contract or renderer failure.
    local function publish_model_result(updated, unchanged)
        if type(updated) ~= "table" or type(updated.model) ~= "string"
            or type(updated.effective_at) ~= "string"
        then
            return nil, failure(
                "ModelSelectionContract",
                "Model selection returned an invalid status"
            )
        end
        if unchanged then
            return publish_status(
                "Model already selected: " .. safe_diagnostic(updated.model, 128) .. "."
            )
        end
        local boundary = updated.effective_at == "first-turn"
            and "the first turn" or "the next turn"
        return publish_status(
            "Model selected: " .. safe_diagnostic(updated.model, 128)
                .. "; applies on " .. boundary .. "."
        )
    end

    ---Applies one still-current Model preview through its owning facade.
    --@param owner table Saved or draft Model selection owner.
    --@param preview table Exact preview issued by that owner.
    --@return boolean|nil applied Whether the result was rendered.
    --@return table|nil err Structured stale or publication failure.
    local function apply_model_preview(owner, preview)
        local updated, update_error = coordinator_call(
            owner,
            "apply",
            "ModelSelectionFailure",
            "bound Model selection",
            preview
        )
        if not updated then return nil, update_error end
        return publish_model_result(updated, preview.unchanged == true)
    end

    ---Builds an exact confirmation card for a Model switch disclosure.
    --@param action_id string Local Model action identity.
    --@param preview table Bound Model compatibility preview.
    --@return table lines Before/after, history, reasons, and choices.
    local function model_confirmation_lines(action_id, preview)
        local lines = {}
        for _, line in ipairs(model_summary_lines("from", preview.from)) do
            lines[#lines + 1] = line
        end
        for _, line in ipairs(model_summary_lines("to", preview.to)) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = "reasons: " .. table.concat(preview.reasons, ",")
        lines[#lines + 1] = "history: seq "
            .. tostring(preview.history.first_sequence) .. ".."
            .. tostring(preview.history.last_sequence)
            .. " body-bytes=" .. tostring(preview.history.body_bytes)
            .. " transition-seq="
            .. tostring(preview.history.transition_last_sequence)
        lines[#lines + 1] = "preflight: required="
            .. tostring(preview.preflight.required_tokens)
            .. " window=" .. tostring(preview.preflight.window_tokens)
            .. " tools=" .. tostring(preview.preflight.tools)
            .. " controls=" .. tostring(preview.preflight.controls)
            .. " roles=" .. tostring(preview.preflight.roles)
        lines[#lines + 1] = "usage/amount: unavailable"
        lines[#lines + 1] = "confirm " .. action_id .. " | deny "
            .. action_id .. " | details " .. action_id
        lines[#lines + 1] = "default: deny"
        return lines
    end

    ---Lists or previews a Model selection from the current Session.
    --@param request table Parsed Model command.
    --@return boolean|nil handled Whether catalog or preview was rendered.
    --@return table|nil err Structured selector or preflight failure.
    local function select_model(request)
        if model_change then
            return nil, failure(
                "ModelSelectionPending",
                "resolve the pending Model selection before starting another"
            )
        end
        local owner = active_model_owner()
        if request.selector == nil then
            local result, list_error = coordinator_call(
                owner,
                "list",
                "ModelSelectionFailure",
                "bounded Model picker"
            )
            if not result then return nil, list_error end
            return publish_model_catalog(result)
        end
        local preview, preview_error = coordinator_call(
            owner,
            "preview",
            "ModelSelectionFailure",
            "Model compatibility and disclosure preview",
            request.selector
        )
        if not preview then return nil, preview_error end
        local valid, validation_error = validate_model_preview(preview)
        if not valid then return nil, validation_error end
        if preview.unchanged or not preview.confirmation_required then
            return apply_model_preview(owner, preview)
        end
        if approval then
            return nil, failure(
                "InteractiveActionUnavailable",
                "resolve the pending Tool approval before confirming a Model change"
            )
        end
        model_change_serial = model_change_serial + 1
        local action_id = "model-change-" .. tostring(model_change_serial)
        model_change = {
            action_id = action_id,
            owner = owner,
            preview = preview,
            lines = model_confirmation_lines(action_id, preview),
        }
        local published, publish_error = publish({
            kind = "action",
            id = action_id,
            lines = model_change.lines,
        })
        if not published then
            model_change = false
            return nil, publish_error
        end
        prompt_needed = true
        return true
    end

    ---Expires a pending Model switch without altering the current selection.
    --@param message string User-visible denial reason.
    --@return boolean|nil denied Whether the action result was rendered.
    --@return table|nil err Structured renderer failure.
    local function deny_model_change(message)
        local action_id = model_change.action_id
        model_change = false
        return publish({
            kind = "action",
            id = action_id,
            text = message or "denied",
        })
    end

    ---Parses a one-shot allow/deny response for a pending Model switch.
    --@param source string Raw confirmation input line.
    --@return boolean|nil handled Whether the response was applied or denied.
    --@return table|nil err Structured invalid or stale confirmation.
    local function route_model_confirmation_line(source)
        local normalized = trim_coordinator_line(source)
        if normalized == "" then return deny_model_change("denied by default") end
        local action_id = normalized:match("^confirm%s+(%S+)$")
        if action_id then
            if action_id ~= model_change.action_id then
                return nil, failure(
                    "ModelSelectionStale",
                    "Model confirmation identity is stale"
                )
            end
            local pending = model_change
            model_change = false
            local applied, apply_error = apply_model_preview(
                pending.owner,
                pending.preview
            )
            if not applied then return nil, apply_error end
            return publish({
                kind = "action",
                id = pending.action_id,
                text = "confirmed and applied at its declared turn boundary",
            })
        end
        action_id = normalized:match("^deny%s+(%S+)$")
        if action_id then
            if action_id ~= model_change.action_id then
                return nil, failure(
                    "ModelSelectionStale",
                    "Model confirmation identity is stale"
                )
            end
            return deny_model_change("denied")
        end
        action_id = normalized:match("^details%s+(%S+)$")
        if action_id then
            if action_id ~= model_change.action_id then
                return nil, failure(
                    "ModelSelectionStale",
                    "Model confirmation identity is stale"
                )
            end
            return publish({
                kind = "details",
                id = model_change.action_id,
                lines = model_change.lines,
            })
        end
        return nil, failure(
            "ModelSelectionRequired",
            "use confirm <model-change-id>, deny <model-change-id>, or details <model-change-id>"
        )
    end

    ---Stages a typed Agent action and renders its exact accepted result.
    --@param method string AgentLoop method name.
    --@param message table Typed action payload.
    --@return boolean|nil applied Whether the action was rendered.
    --@return table|nil err Structured Runtime or renderer failure.
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
        if method == "ask" then
            ask_focus_id = result.ask_id
            return publish_status(
                "Ask request accepted: " .. tostring(result.ask_id)
            )
        end
        return publish_status("Input accepted.")
    end

    ---Displays the current ordered durable user queue.
    --@param none No arguments.
    --@return boolean|nil listed Whether queue rows were rendered.
    --@return table|nil err Structured Runtime or renderer failure.
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

    ---Renders bounded Context selector choices and their state labels.
    --@param result table Context browser search or list result.
    --@return boolean|nil published Whether choices were rendered.
    --@return table|nil err Structured contract or renderer failure.
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

    ---Checks that Agent, Ask, approval, and editor lanes are idle for a switch.
    --@param none No arguments.
    --@return boolean|nil ready True when Context switching can proceed.
    --@return table|nil err Structured busy-lane failure.
    local function context_switch_ready()
        local current_status
        if agent then
            local runtime_status = agent.loop:status()
            local compact_status = agent.compaction:status()
            if runtime_status.state ~= "Idle" and runtime_status.state ~= "WaitingUser" then
                return false, failure(
                    "InteractiveActionUnavailable",
                    "Context switching requires an idle or waiting Agent"
                )
            end
            if compact_status.active == true
                or runtime_status.compaction_preflight_state ~= "idle"
            then
                return false, failure(
                    "InteractiveActionUnavailable",
                    "finish or cancel compaction before switching Context"
                )
            end
            if runtime_status.queue_count ~= 0 then
                return false, failure(
                    "InteractiveActionUnavailable",
                    "clear or finish every queued item before switching Context"
                )
            end
            if runtime_status.ask_state ~= "idle" then
                return false, failure(
                    "InteractiveActionUnavailable",
                    "finish or cancel the Ask request before switching Context"
                )
            end
            if approval then
                return false, failure(
                    "InteractiveActionUnavailable",
                    "resolve the pending approval before switching Context"
                )
            end
            current_status = agent.draft.status()
        end
        return true, current_status
    end

    ---Reverifies and activates a selected Context with optional Workspace consent.
    --@param preview table Exact Context switch preview.
    --@param confirmation string|nil Literal cross-Workspace confirmation.
    --@return boolean|nil activated Whether the new Context became active.
    --@return table|nil err Structured stale or activation failure.
    local function activate_context(preview, confirmation)
        local ready, ready_error = context_switch_ready()
        if not ready then return nil, ready_error end
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
            preview,
            confirmation
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
            or type(next_agent.models) ~= "table"
            or type(next_agent.models.list) ~= "function"
            or type(next_agent.models.preview) ~= "function"
            or type(next_agent.models.apply) ~= "function"
            or type(next_agent.tools) ~= "table"
            or type(next_agent.compaction) ~= "table"
            or type(next_agent.draft) ~= "table"
            or type(next_status) ~= "table"
            or next_status.logical_path ~= preview.logical_path
            or next_status.context_hash ~= preview.context_hash
            or next_status.workspace ~= preview.recorded_workspace
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
        ask_draft = ""
        ask_draft_id = false
        ask_focus_id = false
        last_wait_key = false
        tool_ids = {}
        return publish_status(
            "Context switched: " .. tostring(next_status.display_name)
                .. " [" .. tostring(next_status.context_hash) .. "]"
                .. " workspace=" .. tostring(next_status.workspace)
        )
    end

    ---Lists, previews, or activates a Context from a parsed switch command.
    --@param request table Parsed Context selector action.
    --@return boolean|nil handled Whether the action was rendered.
    --@return table|nil err Structured selection or activation failure.
    local function switch_context(request)
        if model_change then
            return nil, failure(
                "InteractiveActionUnavailable",
                "resolve the pending Model confirmation before switching Context"
            )
        end
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

        local ready, current_status = context_switch_ready()
        if not ready then return nil, current_status end
        if agent then
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

        if preview.requires_workspace_confirmation == true then
            if type(preview.origin_workspace) ~= "string" then
                return nil, failure("ContextSwitchContract", "workspace confirmation has no origin")
            end
            context_change = preview
            return publish({ kind = "details", id = "context-workspace", lines = {
                "Current workspace: " .. safe_diagnostic(preview.origin_workspace, 1024),
                "Context workspace: " .. safe_diagnostic(preview.recorded_workspace, 1024),
                "Future tools use the Context workspace. History is not moved or replayed.",
                "Type CONTINUE " .. preview.context_hash .. " to confirm, or .cancel.",
            } })
        end
        return activate_context(preview)
    end

    ---Routes a typed chat command to queue, Ask, steer, review, or Session owner.
    --@param request table Parsed semantic Agent action.
    --@return boolean|nil handled Whether the action was accepted and rendered.
    --@return table|nil err Structured invalid, busy, or durability failure.
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
        if request.id == "ask" then
            return stage_and_apply("ask", request.message)
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
            if ask_focus_id ~= false
                and current.active_ask_id == ask_focus_id
                and current.ask_state == "cancelling"
            then
                return publish_status("Ask cancellation is already pending.")
            end
            if ask_focus_id ~= false
                and current.active_ask_id == ask_focus_id
                and current.ask_state == "active"
            then
                local result, action_error = coordinator_call(
                    agent.loop,
                    "cancel_ask",
                    "CancelFailure",
                    "ask cancellation",
                    {
                        ask_id = ask_focus_id,
                        reason = "user-cancel",
                        expected_context_generation = current.context_generation,
                        expected_turn_id = current.turn_id,
                    }
                )
                if not result then return nil, action_error end
                if result.cancel_pending ~= true then ask_focus_id = false end
                return publish_status("Ask cancellation requested.")
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
        return nil, failure(
            "InteractiveActionUnavailable",
            "this registered chat action is not attached to the active coordinator"
        )
    end

    ---Publishes the first Context turn and composes its durable Agent owner.
    --@param message string First user input.
    --@param lane string Main or Ask first lane.
    --@return boolean|nil started Whether Agent admission succeeded.
    --@return table|nil err Structured publication or composition failure.
    local function start_first_agent(message, lane)
        local constructed, agent_error = coordinator_function(
            admitted_ports.agent_factory,
            "AgentCompositionFailure",
            "published production Agent construction",
            message,
            "terminal",
            lane or "main"
        )
        if not constructed then
            local draft_status = admitted_ports.chat.draft.status()
            if draft_status.lifecycle == "closed" then
                deferred_failure = agent_error
                lifecycle = "closing"
            end
            return nil, agent_error
        end
        if type(constructed) ~= "table"
            or type(constructed.loop) ~= "table"
            or type(constructed.driver) ~= "table"
            or type(constructed.session) ~= "table"
            or type(constructed.settings) ~= "table"
            or type(constructed.settings.status) ~= "function"
            or type(constructed.settings.update) ~= "function"
            or type(constructed.models) ~= "table"
            or type(constructed.models.list) ~= "function"
            or type(constructed.models.preview) ~= "function"
            or type(constructed.models.apply) ~= "function"
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
        local published, publish_error
        if lane == "ask" then published, publish_error = stage_and_apply("ask", message)
        else published, publish_error = publish({ kind = "user", text = message }) end
        if not published then return nil, publish_error end
        local status = agent.draft.status()
        published, publish_error = publish_status(
            "Context saved: " .. tostring(status.display_name)
                .. " [" .. tostring(status.context_hash) .. "]"
        )
        if not published then return nil, publish_error end
        return true
    end

    ---Records an exact one-shot Tool approval or rejection.
    --@param answer string Allow or deny decision.
    --@return boolean|nil recorded Whether the decision was committed and rendered.
    --@return table|nil err Structured stale or durability failure.
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

    ---Parses the pending Tool approval response from one input line.
    --@param source string Raw user input line.
    --@return boolean|nil handled Whether approval was applied or denied.
    --@return table|nil err Structured invalid or stale approval.
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

    ---Parses one interactive line into a typed chat command.
    --@param source string Raw user input line.
    --@return table|nil request Parsed semantic command.
    --@return table|nil err Structured usage failure.
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

    ---Routes one user line through the active approval, editor, or Agent lane.
    --@param source string Raw user input line.
    --@return boolean|nil handled Whether input was accepted.
    --@return table|nil err Structured command or runtime failure.
    local function route_line(source)
        if multiline then
            if source == ".cancel" then
                multiline, multiline_bytes = false, 0
                return publish_status("Multiline draft discarded.")
            elseif source == ".quit" then
                multiline, multiline_bytes = false, 0
                -- Continue through the ordinary session close path below.
            elseif source == ".clear" then
                multiline, multiline_bytes = {}, 0
                return publish_status("Multiline draft cleared.")
            elseif source == ".show" then
                return publish({ kind = "details", id = "multiline", text = table.concat(multiline, "\n") })
            elseif source == ".submit" or source == ".ask" or source == ".immediate" then
                local message = table.concat(multiline, "\n")
                if message == "" then return nil, failure("DraftEmpty", "multiline draft is empty") end
                local lane = source == ".ask" and "ask" or (source == ".immediate" and "steer" or "submit")
                local accepted, action_error
                if agent then accepted, action_error = stage_and_apply(lane, message)
                elseif lane == "steer" then
                    return nil, failure("NoMainTurn", "immediate input requires an active main turn")
                else accepted, action_error = start_first_agent(message, lane == "ask" and "ask" or "main") end
                if accepted then multiline, multiline_bytes = false, 0 end
                return accepted, action_error
            else
                if source:sub(1, 2) == ".." then source = source:sub(2) end
                local size = multiline_bytes + #source + (#multiline > 0 and 1 or 0)
                if size > admitted.maximum_draft_bytes then
                    return nil, failure("DraftLimit", "multiline draft exceeds its byte limit")
                end
                multiline[#multiline + 1], multiline_bytes = source, size
                return true
            end
        end
        if prompt_edit then
            local handled, editor_error, chat_source = route_prompt_editor(source)
            if not chat_source then return handled, editor_error end
            source = chat_source
        end
        local normalized = trim_coordinator_line(source)
        if context_change and normalized:sub(1, 1) ~= "." then
            local preview = context_change
            context_change = false
            if source ~= "CONTINUE " .. preview.context_hash then
                return publish_status("Context continuation cancelled; the current session remains open.")
            end
            return activate_context(preview, source)
        end
        if approval and normalized:sub(1, 1) ~= "." then
            return route_approval_line(source)
        end
        if model_change and normalized:sub(1, 1) ~= "." then
            return route_model_confirmation_line(source)
        end
        if normalized == "" then return true end
        local request, parse_error = parse_chat(source)
        if not request then return nil, parse_error end
        if request.id == "quit" then
            local cancelled, cancel_error = cancel_prompt_edit("session is closing")
            if not cancelled then return nil, cancel_error end
            lifecycle = "closing"
            return publish_status("Closing the current session.")
        end
        if request.id == "status-chat" then
            return publish({ kind = "details", id = "status", lines = status_lines() })
        end
        if request.id == "help-chat" then return show_help(request.topic) end
        if request.id == "details" then return show_details(request.error_id) end
        if context_change then
            if request.id == "cancel" then
                context_change = false
                return publish_status("Context continuation cancelled; the current session remains open.")
            end
            return nil, failure("InteractiveActionUnavailable", "confirm or cancel the pending workspace change first")
        end
        if request.id == "cautious" then return apply_cautious(request) end
        if request.id == "prompt-edit" then return apply_prompt(request) end
        if request.id == "select-model" then return select_model(request) end
        if request.id == "select-context" then return switch_context(request) end
        if request.id == "multiline" then
            multiline, multiline_bytes = {}, 0
            return publish_status("Multiline input: .submit | .ask | .immediate | .show | .clear | .cancel; use .. for a literal leading dot.")
        end
        if not agent then
            if request.id == "queue-add" then
                return start_first_agent(request.message)
            end
            if request.id == "ask" then
                return start_first_agent(request.message, "ask")
            end
            return nil, failure(
                "NoSavedContext",
                "send the first main message before using this chat action"
            )
        end
        return route_agent_action(request)
    end

    ---Consumes one terminal submission without interpreting render output.
    --@param intent table Typed terminal submit event.
    --@return boolean|nil handled Whether the submitted input was routed.
    --@return table|nil err Structured input or command failure.
    local function handle_submission(intent)
        if context_change and intent ~= "submit-or-queue" then
            return nil, failure("InteractiveActionUnavailable", "confirm or cancel the pending workspace change first")
        end
        if prompt_edit and intent ~= "submit-or-queue" then
            return nil, failure("PromptEditorBusy", "save or cancel the Prompt editor before using another input lane")
        end
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
            result, action_error = stage_and_apply("ask", input_draft)
        end
        if result or prompt_edit then input_draft = "" end
        draft_rejected = not result and input_draft ~= ""
        prompt_needed = lifecycle ~= "closing"
        return result, action_error
    end

    ---Routes a terminal cancel gesture to the innermost active interaction.
    --@param none No arguments.
    --@return boolean|nil handled Whether cancellation was accepted.
    --@return table|nil err Structured cancellation failure.
    local function handle_cancel()
        if prompt_edit then return cancel_prompt_edit("cancelled") end
        if input_draft ~= "" then
            input_draft = ""
            draft_rejected = false
            prompt_needed = true
            return publish_status("Input draft cleared.")
        end
        if multiline then
            multiline, multiline_bytes = false, 0
            return publish_status("Multiline draft discarded.")
        end
        if context_change then
            context_change = false
            return publish_status("Context continuation cancelled; the current session remains open.")
        end
        if model_change then return deny_model_change("denied") end
        if approval then return record_approval("deny") end
        if not agent then return publish_status("Nothing to cancel.") end
        return route_agent_action({ id = "cancel" })
    end

    ---Reduces one typed terminal event into draft, command, or close state.
    --@param event table Native terminal event.
    --@return boolean|nil handled Whether the event was reduced.
    --@return table|nil err Structured terminal or command failure.
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
                or (draft_rejected and 0 or #input_draft) + #event.text
                    > admitted.maximum_draft_bytes
            then
                return nil, failure("DraftLimit", "terminal draft exceeds its byte limit")
            end
            -- A submitted line is no longer in the host's cooked editor.
            -- Keep rejected text available for cancel/retry, but new input
            -- starts a replacement line instead of silently appending to it.
            if draft_rejected then input_draft, draft_rejected = "", false end
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
            or event.action == "ask"
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

    ---Joins, restores, and closes the terminal after coordinator completion.
    --@param none No arguments.
    --@return boolean|nil closed Whether terminal restoration succeeded.
    --@return table|nil err Structured terminal lifecycle failure.
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

    ---Closes the active Agent and waits for its durable activities to settle.
    --@param reason string Reason recorded by the session close path.
    --@return boolean|nil closed Whether the draft and Agent closed cleanly.
    --@return table|nil err Structured close or timeout failure.
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

    ---Closes both owners and reports the final interactive outcome.
    --@param primary_error table|nil Earlier failure that takes precedence.
    --@return table|nil result Immutable successful interactive result.
    --@return table|nil err Structured run or close failure.
    local function finish_run(primary_error)
        prompt_edit = false
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
    --@param self table ApplicationCoordinator instance.
    --@return table|nil result Immutable successful interactive result.
    --@return table|nil err Structured terminal, Agent, renderer, or close failure.
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
                local focus = (approval or model_change or context_change) and "approval" or "chat"
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

    ---Reports the current terminal, Context, and pending action state.
    --@param self table ApplicationCoordinator instance.
    --@return table status Immutable coordinator status snapshot.
    function coordinator:status()
        return readonly({
            lifecycle = lifecycle,
            terminal_started = terminal_started,
            terminal_ended = terminal_ended,
            terminal_outcome = terminal_outcome,
            context_saved = agent ~= false,
            draft_bytes = #input_draft,
            approval_action_id = approval and approval.action_id or false,
            model_change_action_id = model_change
                and model_change.action_id or false,
            context_change_hash = context_change and context_change.context_hash or false,
            diagnostic_count = #diagnostic_order,
            prompt_editor_id = prompt_edit and prompt_edit.id or false,
            prompt_editor_bytes = prompt_edit and #prompt_edit.draft or 0,
        }, "ApplicationCoordinator status")
    end

    return readonly(coordinator, "ApplicationCoordinator")
end

---Creates the cooked-terminal transcript view for a production chat.
--@param composed table Production runtime composition and data layout.
--@param runtime table CLI output ports.
--@return table|nil view Read-only transcript view.
--@return table|nil err Structured output or renderer failure.
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
    -- Production chat uses the host's cooked line editor on every platform.
    -- Advertise only keys that this actual input path delivers independently.
    local renderer, renderer_error = tui.new({
        width = 80,
        capabilities = {
            ansi = false,
            color = false,
            unicode = true,
            keys = {
                Enter = true,
                ["Ctrl+Enter"] = false,
                ["Shift+Enter"] = false,
                ["Alt+Enter"] = false,
                Esc = false,
            },
        },
        maximum_block_bytes = 524288,
        maximum_line_bytes = 262144,
        maximum_id_bytes = 256,
        writer = runtime.stdout,
    })
    if not renderer then return nil, renderer_error end
    local view = {}

    ---Writes a fully rendered transcript block to standard output.
    --@param bytes string Rendered output bytes.
    --@return boolean|nil written Whether all bytes were written.
    --@return table|nil err Structured broken-output failure.
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
    --@param self table Production chat view.
    --@param status table Chat startup status.
    --@return boolean|nil written Whether startup output was written.
    --@return table|nil err Structured renderer or output failure.
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
    --@param self table Production chat view.
    --@param block table Semantic transcript block.
    --@return boolean|nil appended Whether the renderer accepted the block.
    --@return table|nil err Structured renderer failure.
    function view:publish(block)
        local rendered, render_error = renderer.append(block)
        if not rendered then return nil, render_error end
        return true
    end

    ---Writes one plain focus prompt without assuming ANSI or cursor movement.
    --@param self table Production chat view.
    --@param focus string Prompt focus lane.
    --@return boolean|nil written Whether the prompt was written.
    --@return table|nil err Structured renderer or output failure.
    function view:prompt(focus)
        local rendered, render_error = renderer.render_prompt(focus)
        if not rendered then return nil, render_error end
        return write_rendered(rendered)
    end

    return readonly(view, "production chat view")
end

---Creates a Context switch port that verifies and activates exact previews.
--@param initial_composed table Initial production runtime composition.
--@param runtime table CLI invocation ports and facts.
--@param dependencies table|nil Optional composition and Agent factories.
--@return table|nil switcher Read-only Context switch port.
--@return table|nil err Structured dependency failure.
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
    local latest_preview

    ---Lists bounded recent Context rows from the current composition.
    --@param self table Context switch port.
    --@return table|nil result Recent Context catalog result.
    --@return table|nil err Structured catalog failure.
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

    ---Previews one Context selector before exact activation.
    --@param self table Context switch port.
    --@param selector string Context selector.
    --@return table|nil preview Verified continuation preview.
    --@return table|nil err Structured preview failure.
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
        latest_preview = result
        return result, result_error
    end

    ---Activates a previously returned preview in a fresh composition.
    --@param self table Context switch port.
    --@param preview table Exact preview returned by this switcher.
    --@param confirmation table|string|nil Confirmation for the selected Context.
    --@return table|nil activation Replacement Agent and chat status.
    --@return table|nil err Structured activation or cleanup failure.
    function switcher:activate(preview, confirmation)
        if preview ~= latest_preview or type(preview) ~= "table"
            or preview.kind ~= "continue-preview"
            or type(preview.context_hash) ~= "string"
            or type(preview.logical_path) ~= "string"
        then
            return nil, failure(
                "ContextSwitchContract",
                "exact Context activation requires a verified preview"
            )
        end
        latest_preview = nil
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
            or type(next_composed.application.continue_preview) ~= "function"
            or type(next_composed.application.preview_continue) ~= "function"
        then
            return nil, failure(
                "ContextSwitchContract",
                "replacement Runtime composition is incomplete"
            )
        end
        local dispatched, chat, dispatch_error = pcall(
            next_composed.application.continue_preview,
            preview,
            confirmation
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
        ---Releases the newly opened writer after failed activation.
        --@param message string Failure detail if writer state is unknown.
        --@return boolean|nil released Whether the writer closed.
        --@return table|nil err Structured writer-release failure.
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
            or type(next_agent.models) ~= "table"
            or type(next_agent.models.list) ~= "function"
            or type(next_agent.models.preview) ~= "function"
            or type(next_agent.models.apply) ~= "function"
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
--@param composed table Production runtime composition.
--@param chat table Ready run-chat or continue-chat bootstrap result.
--@param runtime table CLI invocation ports and exact fd facts.
--@param initial_agent table|nil Already composed idle Agent for continue-chat.
--@return table|nil result Immutable interactive outcome.
--@return table|nil err Structured composition, runtime, or close failure.
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
    local terminal_port
    ---Releases acquired terminal and Context owners after composition fails.
    --@param primary_error table Original composition failure.
    --@return nil result No interactive result.
    --@return table err Original or writer-release failure.
    local function fail_before_coordinator(primary_error)
        if terminal_port then pcall(terminal_port.close, terminal_port) end
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
        else
            local called, closed, close_error = pcall(chat.draft.close)
            if not called or closed == nil then
                return nil, close_error or failure(
                    "ContextLeaseUnknown",
                    "unsaved chat draft release is unknown"
                )
            end
        end
        return nil, primary_error
    end
    local draft_models
    if initial_agent then
        -- A reopened Context already has a saved Model owner and no draft.update.
        draft_models = initial_agent.models
    else
        local draft_models_error
        draft_models, draft_models_error = new_draft_model_selection(
            chat.draft,
            composed.contexts
        )
        if not draft_models then
            return fail_before_coordinator(draft_models_error)
        end
    end
    local terminal_error
    terminal_port, terminal_error = composed.backend.new_terminal("cooked")
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
        draft_models = draft_models,
        context_switch = context_switch,
        initial_agent = initial_agent,
        ---Starts the published Agent when the coordinator saves its draft.
        --@param message string Initial user message.
        --@param source string Source of the initial message.
        --@param lane string Agent activity lane.
        --@return table|nil agent Published Agent composition.
        --@return table|nil err Structured startup failure.
        agent_factory = function(message, source, lane)
            return M.start_published_agent(composed, chat, message, source, lane)
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

---Encodes raw bytes as lowercase hexadecimal for safe diagnostics.
--@param value string Raw bytes.
--@return string encoded Hexadecimal representation.
local function hex_bytes(value)
    local output = {}
    for index = 1, #value do
        output[index] = string.format("%02x", value:byte(index))
    end
    return table.concat(output)
end

---Bounds setup input before displaying it in a diagnostic.
--@param value string Input value.
--@param maximum_source_bytes integer Maximum source bytes retained.
--@return string diagnostic Safe printable diagnostic.
local function model_setup_diagnostic(value, maximum_source_bytes)
    return ascii_diagnostic(value, maximum_source_bytes)
end

---Builds configuration sections for the interactive Model setup.
--@param values table Validated Model setup fields.
--@return table sections Configuration document sections.
local function model_setup_sections(values)
    local model_values = {
        Enabled = values.enabled,
        Protocol = values.protocol,
        Endpoint = values.endpoint,
        RemoteModel = values.remote_model,
        ContextLength = values.context_length,
        MaxOutputTokens = values.max_output_tokens,
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

-- Each interactive surface owns its cancellation code; an unregistered label
-- is a construction defect, not a surface that silently reports another
-- surface's cancellation.
local SETUP_INPUT_CANCEL_CODES = {
    ["Model setup"] = "ModelSetupCancelled",
    ["Configuration"] = "ConfigEditorCancelled",
    ["Context"] = "ContextReplCancelled",
}

---Creates a line-input port with separate cooked and hidden raw modes.
--@param composed table Production backend and clock ports.
--@param runtime table CLI output port.
--@param label string|nil Input surface label and cancellation identity.
--@return table|nil input Interactive input port.
--@return table|nil err Structured input setup failure.
local function new_model_setup_input(composed, runtime, label)
    label = label or "Model setup"
    local cancel_code = SETUP_INPUT_CANCEL_CODES[label]
    if not cancel_code then
        return nil, failure(
            "InvalidSetupInput",
            "interactive input label has no registered cancellation code"
        )
    end
    local text = require("text")
    local active = false
    local active_mode = false
    local terminal_ended = false
    local pending_events, pending_index = {}, 1
    local input = {}

    ---Writes a setup prompt or status message completely.
    --@param bytes string Output bytes.
    --@return boolean|nil written Whether the write completed.
    --@return table|nil err Structured output failure.
    local function output(bytes)
        if not write_direct(runtime.stdout, bytes) then
            return nil, failure("BrokenStdout", label .. " output could not be completed")
        end
        return true
    end

    ---Reads the validated monotonic clock for terminal operations.
    --@param none No arguments.
    --@return integer|nil value Monotonic timestamp.
    --@return table|nil err Structured clock failure.
    local function now()
        local called, value = pcall(composed.backend.clock_port.monotonic_now)
        if not called or not valid_integer(value, 0) then
            return nil, failure("MonotonicClockDegraded", label .. " clock is unavailable")
        end
        return value
    end

    ---Cancels, joins, and restores any active terminal input mode.
    --@param none No arguments.
    --@return boolean|nil closed Whether terminal restoration completed.
    --@return table|nil err Structured terminal or clock failure.
    local function close_active()
        if not active then return true end
        local observed_now, clock_error = now()
        if not observed_now then
            -- Restoration does not require a clock or a successful join. Never
            -- leave a raw secret field active after a degraded timing port.
            local close_called, closed = pcall(active.close, active)
            active, active_mode, terminal_ended = false, false, false
            pending_events, pending_index = {}, 1
            if not close_called or closed ~= true then
                return nil, failure("TerminalFailure", label .. " terminal state could not be restored")
            end
            return nil, clock_error
        end
        local primary_error
        if not terminal_ended then
            local cancel_called, cancelled = pcall(active.cancel, active, observed_now)
            if not cancel_called or cancelled ~= true then
                primary_error = failure(
                    "TerminalFailure",
                    label .. " input cancellation could not be requested"
                )
            else
                for _ = 1, 1024 do
                    local poll_called, events = pcall(active.poll, active, observed_now, 128)
                    if not poll_called or type(events) ~= "table" then
                        primary_error = primary_error or failure(
                            "TerminalFailure",
                            label .. " cancellation outcome could not be observed"
                        )
                        break
                    end
                    for _, event in ipairs(events) do
                        if type(event) ~= "table" then
                            primary_error = primary_error or failure(
                                "TerminalFailure",
                                label .. " cancellation emitted an invalid event"
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
                            label .. " cancellation wait failed"
                        )
                        break
                    end
                end
                if not terminal_ended then
                    primary_error = primary_error or failure(
                        "TerminalFailure",
                        label .. " cancellation did not reach terminal truth"
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
                label .. " input could not be joined"
            )
        end
        local close_called, closed = pcall(active.close, active)
        if not close_called or closed ~= true then
            primary_error = primary_error or failure(
                "TerminalFailure",
                label .. " terminal state could not be restored"
            )
        end
        active = false
        active_mode = false
        terminal_ended = false
        pending_events, pending_index = {}, 1
        if primary_error then return nil, primary_error end
        return true
    end

    ---Switches the input terminal to cooked or hidden raw mode.
    --@param mode string Requested terminal input mode.
    --@return boolean|nil active Whether the mode started.
    --@return table|nil err Structured mode-transition failure.
    local function activate(mode)
        if active_mode == mode then return true end
        if pending_index <= #pending_events then
            pending_events, pending_index = {}, 1
            return nil, failure("InputModeBoundary", "enter hidden values only after their separate input prompt")
        end
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
                label .. " terminal input could not start"
            )
        end
        active = terminal
        active_mode = mode
        terminal_ended = false
        return true
    end

    ---Removes the final UTF-8 scalar after a hidden-input backspace.
    --@param value string Current hidden input.
    --@return string shortened Input without its final scalar.
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

    ---Applies raw hidden-input bytes with backspace and limit checks.
    --@param value string Current hidden input.
    --@param chunk string Newly received raw bytes.
    --@param maximum_bytes integer Allowed hidden-input byte length.
    --@return string|nil appended Updated hidden input.
    --@return table|nil err Structured control-byte or length failure.
    local function append_raw(value, chunk, maximum_bytes)
        local current = value
        for index = 1, #chunk do
            local byte = chunk:byte(index)
            if byte == 0x08 or byte == 0x7F then
                current = remove_last_scalar(current)
            elseif byte < 0x20 then
                return nil, failure(
                    "InvalidSecretInput",
                    label .. " hidden input contains an unsupported control byte"
                )
            else
                if #current >= maximum_bytes then
                    return nil, failure("InputLimit", label .. " input exceeds its byte limit")
                end
                current = current .. string.char(byte)
            end
        end
        return current
    end

    ---Reads one UTF-8 line, using raw mode for secret fields.
    --@param prompt string Prompt displayed before reading.
    --@param secret boolean Whether to hide and separately collect input.
    --@param maximum_bytes integer Maximum input byte length.
    --@return string|false|nil value Line, cancellation marker, or failure.
    --@return table|nil err Structured read failure or cancellation code.
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
            if pending_index > #pending_events then
                local called, events = pcall(active.poll, active, observed_now, 128)
                if not called or type(events) ~= "table" then
                    return nil, failure(
                        "TerminalPollFailure",
                        label .. " input polling failed"
                    )
                end
                pending_events, pending_index = events, 1
            end
            local progressed = false
            while pending_index <= #pending_events do
                local event = pending_events[pending_index]
                pending_index = pending_index + 1
                progressed = true
                if event.kind == "io_terminal" then
                    terminal_ended = true
                    return false, { code = cancel_code }
                end
                if event.kind ~= "user_action" then
                    return nil, failure(
                        "TerminalContract",
                        label .. " received an invalid terminal event"
                    )
                end
                if event.action == "cancel" or event.action == "eof" then
                    return false, { code = cancel_code }
                elseif event.action == "text" then
                    if type(event.text) ~= "string" then
                        return nil, failure(
                            "TerminalContract",
                            label .. " text event is invalid"
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
                                label .. " input exceeds its byte limit"
                            )
                        end
                        value = value .. event.text
                    end
                elseif event.action == "submit-or-queue" then
                    local valid, utf8_error = text.validate_utf8(value)
                    if not valid then
                        return nil, utf8_error or failure(
                            "InvalidInputEncoding",
                            label .. " input is not valid UTF-8"
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
                        label .. " accepts text, Enter, Esc, or EOF"
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
                        label .. " input wait failed"
                    )
                end
            end
        end
    end

    ---Writes text through the setup output port.
    --@param bytes string Output bytes.
    --@return boolean|nil written Whether the write completed.
    --@return table|nil err Structured output failure.
    function input.write(bytes)
        return output(bytes)
    end

    ---Closes and restores the current terminal input mode.
    --@param none No arguments.
    --@return boolean|nil closed Whether restoration completed.
    --@return table|nil err Structured terminal failure.
    function input.close()
        return close_active()
    end

    return input
end

---Reports a cancelled Model setup without persisting a draft.
--@param input table Active setup input/output port.
--@return table|nil result Immutable cancellation result.
--@return table|nil err Structured output failure.
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

---Inspects stable Context references before removing a Model binding.
--@param contexts table Context catalog and store services.
--@return table|nil bindings Immutable verified Model references.
--@return table|nil err Structured incomplete or stale scan failure.
local function model_context_references(contexts)
    if type(contexts) ~= "table" or type(contexts.store) ~= "table"
        or type(contexts.store.inspect_import) ~= "function"
    then
        return nil, failure("ModelImpactUnavailable", "Context reference inspection is unavailable")
    end
    local observed, observe_error = observe_context_catalog(contexts, true)
    if not observed then return nil, observe_error end
    if observed.complete ~= true or #observed.rows ~= #observed.targets then
        return nil, failure("ModelImpactUnavailable", "Context reference scan is incomplete")
    end
    local bindings = {}
    for index, selection in ipairs(observed.targets) do
        if observed.rows[index].header_state ~= "valid" then
            return nil, failure("ModelImpactUnavailable",
                "Close active Context writers and inspect unavailable Contexts before changing Model references")
        end
        local verified = contexts.catalog.verify_target(selection, "open")
        if type(verified) ~= "table" or verified.tag ~= "Verified" then
            return nil, failure("ModelImpactStale", "a Context changed during reference inspection")
        end
        local document, document_error = contexts.store.inspect_import(
            verified.physical_hint, verified.credential
        )
        if not document then return nil, document_error end
        local current = contexts.catalog.verify_target(selection, "open")
        if type(current) ~= "table" or current.tag ~= "Verified"
            or not plain_equal(current.credential, verified.credential)
            or current.logical_path ~= verified.logical_path
        then
            return nil, failure("ModelImpactStale", "a Context changed during reference inspection")
        end
        bindings[#bindings + 1] = {
            hash = verified.hash, logical_path = verified.logical_path,
            physical_path = verified.physical_hint, credential = verified.credential,
            model = document.session.current_model.name,
            generation = document.generation, event_count = document.event_count,
        }
    end
    ---Orders verified bindings by their logical Context paths.
    --@param left table First verified binding.
    --@param right table Second verified binding.
    --@return boolean before Whether the first path sorts earlier.
    table.sort(bindings, function(left, right) return left.logical_path < right.logical_path end)
    local final, final_error = observe_context_catalog(contexts)
    if not final then return nil, final_error end
    if final.complete ~= true or #final.rows ~= #bindings then
        return nil, failure("ModelImpactStale", "Context membership changed during reference inspection")
    end
    ---Orders the second catalog scan for exact membership comparison.
    --@param left table First observed Context row.
    --@param right table Second observed Context row.
    --@return boolean before Whether the first path sorts earlier.
    table.sort(final.rows, function(left, right) return left.logical_path < right.logical_path end)
    for index, row in ipairs(final.rows) do
        if row.logical_path ~= bindings[index].logical_path or row.hash16 ~= bindings[index].hash
            or row.header_state ~= "valid"
        then
            return nil, failure("ModelImpactStale", "Context membership changed during reference inspection")
        end
    end
    for _, selection in ipairs(observed.targets) do
        local verified = contexts.catalog.verify_target(selection, "open")
        if type(verified) ~= "table" or verified.tag ~= "Verified" then
            return nil, failure("ModelImpactStale", "a Context changed during reference inspection")
        end
    end
    return assert(freeze(bindings, {}, "Model reference inspection"))
end

---Collects and validates a new Model draft field by field.
--@param config table Configuration validation service.
--@param input table Interactive setup input/output port.
--@param suggested_name string|nil Initial Model name.
--@param make_draft function Factory validating the complete field set.
--@param require_enabled boolean Whether this Model must remain enabled.
--@return table|false|nil draft Valid draft, cancellation, or failure.
--@return table|nil values Complete values or structured failure.
local function collect_new_model(config, input, suggested_name, make_draft, require_enabled)
    local values = { name = suggested_name or "", protocol = "openai-chat", enabled = true,
        endpoint = "", remote_model = "", context_length = 32768, max_output_tokens = 4096, key = "" }
    local steps = {
        { key = "name", prompt = "Model name", kind = "name" },
        { key = "protocol", prompt = "Protocol (openai-chat|anthropic-messages)", kind = "protocol" },
        { key = "enabled", prompt = "Enable this Model? (yes|no)", kind = "boolean" },
        { key = "endpoint", prompt = "Endpoint", kind = "endpoint" },
        { key = "remote_model", prompt = "Remote model", kind = "remote" },
        { key = "context_length", prompt = "Context length (tokens)", kind = "context" },
        { key = "max_output_tokens", prompt = "Maximum output tokens", kind = "output" },
        { key = "key", prompt = "Key (hidden; empty means no key)", kind = "secret" },
    }
    local written, write_error = input.write("Blank Model draft. .back returns to the previous field; Esc cancels.\n"
        .. "Enter keeps the draft value; .clear empties text. Prefix another dot for literal directives.\n"
        .. "Set token limits within the provider's supported model window.\n")
    if not written then return nil, write_error end
    local index = 1
    while true do
        local step = steps[index]
        local current = values[step.key]
        local default = step.kind == "secret" and ""
            or (step.kind == "endpoint" or step.kind == "remote" or step.kind == "name")
                and (current == "" and "" or " [keep draft]")
            or " [" .. tostring(type(current) == "boolean" and (current and "yes" or "no") or current) .. "]"
        local answer, read_error = input.read(step.prompt .. default .. ": ", step.kind == "secret", 16384)
        if answer == nil then return nil, read_error end
        if answer == false then return false end
        if answer == ".back" then
            if index == 1 then return false end
            index = index - 1
        else
            local value = answer == "" and current or answer
            if answer == ".clear" then value = "" end
            if answer:sub(1, 2) == ".." then value = answer:sub(2) end
            local valid = true
            if step.kind == "name" then
                valid = config.validate_model_name(value) ~= nil
            elseif step.kind == "protocol" then
                valid = value == "openai-chat" or value == "anthropic-messages"
            elseif step.kind == "boolean" then
                if type(value) == "string" then
                    valid = value == "yes" or value == "no"
                    value = value == "yes"
                end
                if valid and require_enabled and not value then
                    valid = false
                    written, write_error = input.write("At least one Model must remain enabled.\n")
                    if not written then return nil, write_error end
                end
            elseif step.kind == "endpoint" or step.kind == "remote" then
                valid = value ~= "" or not values.enabled
            elseif step.kind == "context" or step.kind == "output" then
                if type(value) == "string" then
                    value = #value <= 7 and value:match("^[0-9]+$") and tonumber(value) or nil
                end
                valid = valid_integer(value, step.kind == "context" and 2 or 1)
                    and value <= (step.kind == "context" and 2000000
                        or math.min(131072, values.context_length - 1))
            end
            if valid then
                values[step.key] = value
                if step.kind == "context" then
                    values.max_output_tokens = math.min(values.max_output_tokens, value - 1)
                end
                if index < #steps then
                    index = index + 1
                else
                    local draft, draft_error = make_draft(values)
                    if draft then return draft, values end
                    written, write_error = input.write("Model draft failed complete validation: "
                        .. safe_diagnostic(draft_error and draft_error.code or "ConfigInvalid", 128)
                        .. (draft_error and draft_error.reason and " / " .. safe_diagnostic(draft_error.reason, 128) or "")
                        .. ". Use .back to correct earlier fields.\n")
                    if not written then return nil, write_error end
                end
            else
                written, write_error = input.write("That value is invalid for " .. step.prompt .. ".\n")
                if not written then return nil, write_error end
            end
        end
    end
end

---Manages private Model drafts; a separate confirmed action tests saved Models.
--@param composed table Production runtime composition.
--@param runtime table CLI invocation ports.
--@return table|nil result Immutable Model manager outcome.
--@return table|nil err Structured manager failure.
function M.run_model_manager(composed, runtime)
    local config = composed.config
    local base, begin_error = config.begin_edit(composed.layout.config_path)
    if not base then return nil, begin_error end
    local draft, revision, changes, plan = base, 1, {}, nil
    local test_results, online_requests = {}, 0
    local input, input_error = new_model_setup_input(composed, runtime)
    if not input then return nil, input_error end
    ---Builds the current revision-bound Model editor identity.
    --@param none No arguments.
    --@return string id Current editor identity.
    local function editor_id() return "model-edit-" .. tostring(revision) end
    ---Derives validated Model generation data from a draft.
    --@param candidate table|nil Draft override.
    --@return table generation Validated configuration generation.
    local function generation(candidate) return assert(config.draft_generation(candidate or draft)) end
    ---Redacts registered secrets before showing an editor value.
    --@param value any Value to display.
    --@return string shown Safe diagnostic string.
    local function display(value)
        local source = tostring(value)
        for _, candidate in ipairs({ base, draft }) do
            for _ in pairs(assert(generation(candidate).scan_registered_secrets(source))) do
                return "[hidden]"
            end
        end
        return ascii_diagnostic(source, 16384)
    end
    ---Formats one Model row with its active capabilities and test state.
    --@param name string Model name.
    --@param index integer Position in the Model order.
    --@return string line Display row.
    local function model_line(name, index)
        local model = generation().models[name]
        local endpoint = normalized_endpoint_identity(model.endpoint)
        return editor_id() .. ":" .. tostring(index) .. " " .. display(name)
            .. " enabled=" .. tostring(model.enabled) .. " default=" .. tostring(index == 1)
            .. " current=none protocol=" .. display(model.protocol)
            .. " remote=" .. display(model.remote_model or "(unset)")
            .. " origin=" .. (endpoint and display(endpoint.origin) or "(unset)")
            .. " streaming=" .. tostring(model.streaming) .. " tools=" .. tostring(model.tools_enabled)
            .. " key=" .. (model.key_configured and "set" or "missing")
            .. " test=" .. (test_results[name] or "untested")
    end
    ---Formats a Model field while hiding secrets and endpoint queries.
    --@param row table Model draft field.
    --@return string value Safe field text.
    local function field_value(row)
        if row.hidden then return row.configured and "[hidden; configured]" or "[hidden; default]" end
        if not row.has_value then return "(unset)" end
        if row.key == "Endpoint" then
            local endpoint = normalized_endpoint_identity(row.value)
            return endpoint and display(endpoint.origin .. endpoint.route:gsub("%?.*$", "?configured"))
                or "(unavailable)"
        end
        return display(row.value) .. (row.configured and "" or " (default)")
    end
    ---Writes one bounded page of Model rows.
    --@param page integer One-based Model page.
    --@return boolean|nil written Whether the page was written.
    --@return table|nil err Structured page or output failure.
    local function list(page)
        local order = generation().model_order
        local first = (page - 1) * 32 + 1
        if first > #order then return nil, failure("ModelEditorPage", "Model page is out of range") end
        local lines = { "MODELS " .. editor_id() .. " total=" .. tostring(#order) }
        for index = first, math.min(first + 31, #order) do
            lines[#lines + 1] = model_line(order[index], index)
        end
        if first + 31 < #order then lines[#lines + 1] = "Next: list " .. tostring(page + 1) end
        return input.write(table.concat(lines, "\n") .. "\n")
    end
    ---Builds the immutable Model manager result.
    --@param outcome string Manager outcome.
    --@param state string Terminal editor state.
    --@param committed table|nil Committed configuration generation.
    --@return table result Immutable manager result.
    local function result(outcome, state, committed)
        return readonly({ action = "model-repl", outcome = outcome, state = state,
            config_path = composed.layout.config_path,
            config_generation = committed and committed.id or false,
            online_requests = online_requests }, "Model editor result")
    end
    ---Advances the draft revision after a validated Model edit.
    --@param candidate table Replacement private draft.
    --@param change string Human-readable change summary.
    --@return boolean|nil written Whether the revision notice was written.
    --@return table|nil err Structured limit or output failure.
    local function advance(candidate, change)
        if revision == math.maxinteger or #changes >= 256 then
            return nil, failure("ModelEditorLimit", "save or discard the current Model changes first")
        end
        revision, draft, plan = revision + 1, candidate, nil
        test_results = {}
        changes[#changes + 1] = change
        return input.write("Draft " .. editor_id() .. " validated. Use list for current row identities; preview before save.\n")
    end
    ---Displays a complete Model diff and binds the save confirmation.
    --@param none No arguments.
    --@return boolean|nil shown Whether the preview was written.
    --@return table|nil err Structured reference-scan or output failure.
    local function preview()
        plan = nil
        local before, after = generation(base), generation()
        local lines = { "MODEL PREVIEW " .. editor_id() .. " changes=" .. tostring(#changes),
            "Default Model: " .. display(before.model_order[1]) .. " -> " .. display(after.model_order[1]) }
        for _, change in ipairs(changes) do
            lines[#lines + 1] = display(change)
        end
        for index, name in ipairs(after.model_order) do
            if before.model_order[index] ~= name or not before.models[name] then
                lines[#lines + 1] = model_line(name, index)
            end
            if not before.models[name] then
                for _, row in ipairs(assert(config.draft_fields(draft, "Model." .. name))) do
                    lines[#lines + 1] = "  " .. row.key .. " = " .. field_value(row)
                end
            end
        end
        for _, key in ipairs({ "ActionReviewModel", "TerminationReviewModel" }) do
            local old, new = before.get("Agent", key), after.get("Agent", key)
            if old ~= new then
                lines[#lines + 1] = "Agent." .. key .. ": " .. display(old) .. " -> " .. display(new)
            end
        end
        local affected = {}
        for _, name in ipairs(before.model_order) do
            if not after.models[name] or (before.models[name].enabled and not after.models[name].enabled) then
                affected[name] = true
            end
        end
        local references
        if next(affected) then
            local reference_error
            references, reference_error = model_context_references(composed.contexts)
            if not references then return nil, reference_error end
            local count = 0
            for _, binding in ipairs(references) do
                if affected[binding.model] then
                    count = count + 1
                    lines[#lines + 1] = "Context " .. binding.hash .. " " .. display(binding.logical_path)
                        .. " references " .. display(binding.model)
                end
            end
            lines[#lines + 1] = "Affected Contexts: " .. tostring(count)
            lines[#lines + 1] = "Context XML and history stay unchanged. A missing or disabled Model requires explicit mapping on continuation."
        end
        lines[#lines + 1] = "Complete configuration: valid. Agent ready: " .. tostring(after.agent_ready)
            .. ". Connection test: untested."
        for _, warning in ipairs(after.warnings) do
            lines[#lines + 1] = "WARNING " .. display(warning.code)
        end
        lines[#lines + 1] = "Confirm this preview: save " .. editor_id()
        local shown, show_error = input.write(table.concat(lines, "\n") .. "\n")
        if shown then plan = { revision = revision, references = references } end
        return shown, show_error
    end
    ---Applies one validated Model operation to the private draft.
    --@param command table Parsed Model editor command.
    --@param name string Selected Model name.
    --@return boolean|false|nil handled Edit output, cancellation, or failure.
    --@return table|nil err Structured validation or input failure.
    local function edit(command, name)
        if command.operation == "rename" or command.operation == "delete" or command.operation == "move" then
            local candidate, edit_error = config.manage_model(draft, command.operation, name,
                command.operation == "rename" and command.name or command.position)
            if not candidate then return nil, edit_error end
            return advance(candidate, command.operation .. " Model." .. name
                .. ((command.name or command.position) and " -> " .. tostring(command.name or command.position) or ""))
        end
        local section = "Model." .. name
        local fields = assert(config.draft_fields(draft, section))
        local selected
        for _, row in ipairs(fields) do if row.key == command.key then selected = row end end
        if not selected then return nil, failure("UnknownConfigField", "Model field is unknown") end
        local candidate, edit_error
        if command.operation == "unset" then
            candidate, edit_error = config.edit_draft(draft,
                { { section = section, key = command.key, value = config.unset } })
        else
            local hint = selected.form == "text" and 'quoted INI text, e.g. "text\\nnext line"'
                or (#selected.values > 0 and table.concat(selected.values, "|") or selected.type)
            local shown, show_error = input.write("Value type: " .. hint
                .. (selected.hidden and "; hidden input" or "") .. ". Esc cancels the editor.\n")
            if not shown then return nil, show_error end
            local value, read_error = input.read("value> ", selected.hidden, 16384)
            if value == false or value == nil then return value, read_error end
            candidate, edit_error = config.edit_draft_value(draft, section, command.key, value)
        end
        if not candidate then return nil, edit_error end
        local after
        for _, row in ipairs(assert(config.draft_fields(candidate, section))) do
            if row.key == command.key then after = row end
        end
        -- Keep values private until display scans the final candidate's secrets.
        local old_draft = draft
        draft = candidate
        local description = section .. "." .. command.key .. ": "
            .. field_value(selected) .. " -> " .. field_value(after)
        draft = old_draft
        return advance(candidate, description)
    end
    ---Runs the Model manager command loop until save or exit.
    --@param none No arguments.
    --@return table|nil result Immutable manager outcome.
    --@return table|nil err Structured editor failure.
    local function run_editor()
        local written, write_error = input.write("YACA MODEL MANAGER\n"
            .. "Configuration draft. Enter help; add starts a blank Model; test checks a saved Model after confirmation.\n")
        if not written then return nil, write_error end
        written, write_error = list(1)
        if not written then return nil, write_error end
        while true do
            local source, read_error = input.read(editor_id() .. "> ", false, 16384)
            if source == false then return model_setup_cancelled(input) end
            if source == nil then return nil, read_error end
            local command, action_error = runtime.cli.parse_model_editor(source, editor_id())
            local handled = command ~= nil
            if command then
                local operation = command.operation
                local name = command.row and generation().model_order[command.row]
                if command.row and not name then
                    handled, action_error = nil, failure("UnknownModel", "Model row is out of range")
                elseif operation == "cancel" or operation == "quit" then
                    written, write_error = input.write("Unsaved Model edits discarded.\n")
                    if not written then return nil, write_error end
                    return result(operation == "quit" and "success" or "cancelled",
                        #changes == 0 and "unchanged" or "discarded")
                elseif operation == "help" then
                    handled, action_error = input.write(assert(runtime.cli.render_help("model-repl")))
                elseif operation == "list" then
                    handled, action_error = list(command.page)
                elseif operation == "show" then
                    local lines = { model_line(name, command.row) }
                    for _, row in ipairs(assert(config.draft_fields(draft, "Model." .. name))) do
                        lines[#lines + 1] = row.key .. " = " .. field_value(row) .. " [" .. row.type .. "]"
                    end
                    handled, action_error = input.write(table.concat(lines, "\n") .. "\n")
                elseif operation == "test" then
                    handled, action_error = nil, nil
                    local saved, saved_error = config.reload_file(composed.layout.config_path)
                    if #changes > 0 then
                        action_error = failure("ModelTestUnsaved", "save and reopen the manager before testing edited Models")
                    elseif not saved then action_error = saved_error
                    elseif not plain_equal(saved.models[name], generation().models[name])
                        or not plain_equal(saved.network, generation().network)
                        or not plain_equal(saved.general, generation().general)
                        or saved.matches_model_secrets(generation(), name) ~= true
                    then
                        action_error = failure("ModelTestStale", "configuration changed; reload before testing")
                    elseif not saved.models[name].enabled then
                        action_error = failure("ModelTestDisabled", "enable and save the Model before testing")
                    else
                        local row = editor_id() .. ":" .. tostring(command.row)
                        local endpoint = normalized_endpoint_identity(saved.models[name].endpoint)
                        local attempts = 1 + (saved.models[name].retry_count or 0)
                        written, write_error = input.write("Connection test for " .. display(name) .. " at "
                            .. display(endpoint.origin .. endpoint.route:gsub("%?.*$", "?configured"))
                            .. ". Up to " .. tostring(attempts) .. " provider attempts, 1024 output tokens per attempt; API charges may apply.\n"
                            .. "Sends a synthetic probe and configured system prompts; no Context or tools.\n")
                        if not written then return nil, write_error end
                        local answer, answer_error = input.read("Type TEST " .. row .. " to connect: ", false, 128)
                        if answer == nil then return nil, answer_error end
                        if answer ~= "TEST " .. row then
                            handled, action_error = input.write("Connection test cancelled.\n")
                        else
                            handled, action_error = input.close()
                            if not handled then return nil, action_error end
                            local tested = M.check_model_connection(composed, name, saved)
                            online_requests = online_requests + tested.online_requests
                            test_results[name] = tested.outcome
                            handled, action_error = input.write("Connection test " .. display(tested.outcome)
                                .. ": " .. display(tested.summary) .. "\n")
                        end
                    end
                elseif operation == "preview" then
                    handled, action_error = preview()
                elseif operation == "add" then
                    ---Validates the collected fields as a new Model draft.
                    --@param fields table Complete Model setup field values.
                    --@return table|nil draft Validated Model draft.
                    --@return table|nil err Structured configuration failure.
                    local candidate, values = collect_new_model(config, input, nil, function(fields)
                        return config.add_model(draft, fields.name, model_setup_sections(fields)[3].values)
                    end)
                    if candidate == false then
                        handled, action_error = input.write("New Model discarded; existing draft retained.\n")
                    elseif not candidate then handled, action_error = nil, values
                    else handled, action_error = advance(candidate, "add Model." .. values.name) end
                elseif operation == "reset" or operation == "reload" then
                    local candidate = base
                    if operation == "reload" then candidate, action_error = config.begin_edit(composed.layout.config_path) end
                    if candidate then
                        base, draft, changes, plan = candidate, candidate, {}, nil
                        test_results = {}
                        revision = revision + 1
                        handled, action_error = list(1)
                    else handled = nil end
                elseif operation == "save" then
                    if not plan or plan.revision ~= revision then
                        handled, action_error = nil, failure("ModelPreviewRequired", "run preview before confirming save")
                    elseif #changes == 0 then return result("success", "unchanged")
                    else
                        local approved = plan
                        plan = nil
                        ---Rejects publication if referenced Contexts changed after preview.
                        --@param none No arguments.
                        --@return boolean|nil valid Whether references remain identical.
                        --@return table|nil err Structured stale-reference failure.
                        local function guard()
                            if not approved.references then return true end
                            local current, reference_error = model_context_references(composed.contexts)
                            if not current then return nil, reference_error end
                            if not plain_equal(approved.references, current) then
                                return nil, failure("ModelImpactStale", "Context references changed; preview again before saving")
                            end
                            return true
                        end
                        handled, action_error = input.close()
                        if not handled then return nil, action_error end
                        local committed, commit_error
                        for _ = 1, 8 do
                            local random, random_error = composed.backend.system.secure_random(12)
                            if not random then return nil, random_error end
                            committed, commit_error = config.commit_draft(draft,
                                composed.layout.config_path .. ".yaca-edit-" .. hex_bytes(random) .. ".tmp", guard)
                            if committed then break end
                            local code = commit_error and commit_error.code
                            if code ~= "DestinationExists" and code ~= "AlreadyExists" and code ~= "TemporaryConflict" then break end
                        end
                        if committed then
                            written, write_error = input.write(online_requests == 0
                                and "Models published offline. No network request was made.\n"
                                or "Models published. Saving makes no network request.\n")
                            if not written then return nil, write_error end
                            return result("success", "published", committed)
                        end
                        if commit_error and commit_error.code == "ConfigPublishUnknown" then return nil, commit_error end
                        handled, action_error = nil, commit_error
                    end
                else
                    handled, action_error = edit(command, name)
                    if handled == false then return model_setup_cancelled(input) end
                end
            end
            if not handled then
                if action_error and action_error.code == "BrokenStdout" then return nil, action_error end
                written, write_error = input.write("ERROR " .. display(action_error and action_error.code or "ModelEditorFailure")
                    .. ": " .. display(action_error and action_error.message or "Model action failed")
                    .. (action_error and action_error.reason and " (" .. display(action_error.reason) .. ")" or "") .. "\n")
                if not written then return nil, write_error end
            end
        end
    end
    local called, outcome, run_error = pcall(run_editor)
    local closed, close_error = input.close()
    if not closed then return nil, close_error end
    if not called then return nil, failure("ModelEditorFailure", "Model editor failed") end
    return outcome, run_error
end

---Creates the first Model from a fully validated private draft; valid files
-- enter the Model manager. Only the exact bootstrap repair template may be
-- replaced here; arbitrary invalid files require configuration repair.
--@param composed table Production runtime composition.
--@param runtime table CLI invocation ports.
--@return table|nil result Immutable setup or Model manager outcome.
--@return table|nil err Structured setup or publication failure.
function M.run_model_repl(composed, runtime)
    if type(composed) ~= "table" or type(composed.config) ~= "table"
        or type(composed.backend) ~= "table" or type(composed.layout) ~= "table"
        or type(runtime) ~= "table" or type(runtime.cli) ~= "table"
        or type(runtime.cli.parse_model_editor) ~= "function"
    then
        return nil, failure("InvalidModelSetup", "Model setup ports are incomplete")
    end
    local config = composed.config
    local existing, edit_error = config.begin_edit(composed.layout.config_path)
    if existing then return M.run_model_manager(composed, runtime) end
    local mode = edit_error and edit_error.code == "NotFound" and "create" or "repair-template"
    if mode == "repair-template" and read_file_bytes(composed.backend.filesystem,
        composed.layout.config_path, #CONFIG_REPAIR_TEMPLATE) ~= CONFIG_REPAIR_TEMPLATE
    then
        return nil, failure("ConfigRepairRequired", "Use --config-repl to repair the invalid configuration")
    end
    local input, input_error = new_model_setup_input(composed, runtime)
    if not input then return nil, input_error end
    ---Runs first-Model setup through explicit offline publication.
    --@param none No arguments.
    --@return table|nil result Immutable setup outcome.
    --@return table|nil err Structured input or publication failure.
    local function run_setup()
        local written, write_error = input.write("YACA MODEL SETUP\n"
            .. "Offline only. Default Model name: Primary.\n")
        if not written then return nil, write_error end
        ---Validates the first Model against create or exact repair mode.
        --@param fields table Complete Model setup field values.
        --@return table|nil draft Validated configuration draft.
        --@return table|nil err Structured validation failure.
        local draft, values = collect_new_model(config, input, "Primary", function(fields)
            local sections = model_setup_sections(fields)
            if mode == "create" then
                return config.begin_new_values(composed.layout.config_path, sections)
            end
            return config.begin_exact_repair_values(composed.layout.config_path, CONFIG_REPAIR_TEMPLATE, sections)
        end, true)
        if draft == false then return model_setup_cancelled(input) end
        if not draft then return nil, values end
        local generation = assert(config.draft_generation(draft))
        ---Redacts registered secrets in first-Model confirmation text.
        --@param value any Value to display.
        --@return string shown Safe diagnostic text.
        local function display(value)
            for _ in pairs(assert(generation.scan_registered_secrets(tostring(value)))) do return "[hidden]" end
            return model_setup_diagnostic(tostring(value), 1024)
        end
        local endpoint = normalized_endpoint_identity(values.endpoint)
        written, write_error = input.write("Publish Model." .. display(values.name)
            .. " protocol=" .. display(values.protocol)
            .. " endpoint=" .. (endpoint and display(endpoint.origin .. endpoint.route:gsub("%?.*$", "?configured")) or "(unset)")
            .. " remote=" .. display(values.remote_model) .. " enabled=" .. tostring(values.enabled)
            .. " key=" .. (values.key ~= "" and "provided" or "none")
            .. " context=" .. tostring(values.context_length) .. " output=" .. tostring(values.max_output_tokens) .. "\n")
        if not written then return nil, write_error end
        local answer, answer_error = input.read("Type APPLY to publish, or press Enter to cancel: ", false, 128)
        if answer == nil then return nil, answer_error end
        if answer ~= "APPLY" then return model_setup_cancelled(input) end
        local closed, close_error = input.close()
        if not closed then return nil, close_error end
        if mode == "create" then
            local created, root_error = ensure_data_root(composed.backend.filesystem,
                composed.layout.data_root, composed.layout.application_root)
            if created == nil then return nil, root_error end
        end
        local committed, commit_error
        for _ = 1, 8 do
            local random, random_error = composed.backend.system.secure_random(12)
            if not random then return nil, random_error end
            committed, commit_error = config.commit_draft(draft,
                composed.layout.config_path .. ".yaca-edit-" .. hex_bytes(random) .. ".tmp")
            if committed then break end
            local code = commit_error and commit_error.code
            if code ~= "DestinationExists" and code ~= "AlreadyExists" and code ~= "TemporaryConflict" then break end
        end
        if not committed then return nil, commit_error end
        written, write_error = input.write("Model " .. display(values.name)
            .. " was published offline. No network request was made.\n")
        if not written then return nil, write_error end
        return readonly({ action = "model-repl", outcome = "success", state = "published",
            config_path = composed.layout.config_path, model_name = values.name,
            config_generation = committed.id, online_requests = 0 }, "published Model setup")
    end
    local called, outcome, run_error = pcall(run_setup)
    local closed, close_error = input.close()
    if not closed then return nil, close_error end
    if not called then return nil, failure("ModelSetupFailure", "Model setup failed") end
    return outcome, run_error
end

---Repairs an invalid INI through private physical-line edits. The same complete
-- schema and publication transaction validate the result before any write.
--@param composed table Production runtime composition.
--@param runtime table CLI invocation ports.
--@return table|nil result Immutable repair outcome.
--@return table|nil err Structured repair or publication failure.
function M.run_config_repair(composed, runtime)
    if type(composed) ~= "table" or type(composed.config) ~= "table"
        or type(composed.layout) ~= "table" or type(composed.layout.config_path) ~= "string"
        or type(composed.backend) ~= "table" or type(composed.backend.system) ~= "table"
        or type(composed.backend.system.secure_random) ~= "function"
        or type(runtime) ~= "table" or type(runtime.cli) ~= "table"
        or type(runtime.cli.parse_config_repair) ~= "function"
    then
        return nil, failure("InvalidConfigEditor", "configuration repair ports are incomplete")
    end
    local config = composed.config
    for _, method in ipairs({ "begin_repair", "repair_status", "edit_repair", "commit_repair" }) do
        if type(config[method]) ~= "function" then
            return nil, failure("InvalidConfigEditor", "configuration repair service is incomplete")
        end
    end
    local base, begin_error = config.begin_repair(composed.layout.config_path)
    if not base then return nil, begin_error end
    local draft = base
    local revision = 1
    local input, input_error = new_model_setup_input(composed, runtime, "Configuration")
    if not input then return nil, input_error end
    ---Builds the revision-bound configuration repair identity.
    --@param none No arguments.
    --@return string id Current repair identity.
    local function repair_id() return "config-repair-" .. tostring(revision) end
    ---Builds an immutable configuration repair outcome.
    --@param outcome string Repair outcome.
    --@param state string Terminal repair state.
    --@param generation table|nil Published configuration generation.
    --@return table result Immutable repair result.
    local function result(outcome, state, generation)
        return readonly({ action = "config-repl", outcome = outcome, state = state,
            config_path = composed.layout.config_path,
            config_generation = generation and generation.id or false,
            online_requests = 0 }, "configuration repair result")
    end
    ---Shows a bounded physical-line page or redacted repair preview.
    --@param page integer One-based line page.
    --@param preview boolean Whether to display the edit summary.
    --@return table|nil status Configuration repair status.
    --@return table|nil err Structured status or output failure.
    local function show_status(page, preview)
        local status, status_error = config.repair_status(draft, page)
        if not status then return nil, status_error end
        local lines = { "CONFIG REPAIR " .. repair_id() .. " lines=" .. tostring(status.lines),
            status.valid and (status.agent_ready and "SCHEMA VALID / AGENT READY"
                or "SCHEMA VALID / AGENT INELIGIBLE") or "VALIDATION FAILED" }
        if not status.valid then
            lines[#lines + 1] = "Reason: " .. safe_diagnostic(status.reason or "configuration", 128)
                .. (status.syntax_reason and " / " .. safe_diagnostic(status.syntax_reason, 128) or "")
                .. (status.error_line and " at line " .. tostring(status.error_line) or "")
                .. (status.error_column and " column " .. tostring(status.error_column) or "")
        end
        if preview then
            for index, edit in ipairs(status.edits) do
                lines[#lines + 1] = tostring(index) .. ". " .. edit.operation
                    .. " line " .. tostring(edit.line) .. " [contents hidden]"
            end
            lines[#lines + 1] = status.valid and "Save: save " .. repair_id()
                or "Save is blocked until the complete configuration validates."
        else
            for _, row in ipairs(status.rows) do
                lines[#lines + 1] = tostring(row.line) .. ": " .. row.label .. " [contents hidden]"
            end
            if page * 32 < status.lines then lines[#lines + 1] = "Next: list " .. tostring(page + 1) end
        end
        local written, write_error = input.write(table.concat(lines, "\n") .. "\n")
        if not written then return nil, write_error end
        return status
    end
    ---Advances the repair revision after a validated line edit.
    --@param next_draft table Replacement private repair draft.
    --@return boolean|nil advanced Whether the revision advanced.
    --@return table|nil err Structured revision-limit failure.
    local function advance(next_draft)
        if revision >= 1000000 then
            return nil, failure("ConfigRepairLimit", "configuration repair revision limit reached")
        end
        revision = revision + 1
        draft = next_draft
        return true
    end
    ---Runs the physical-line repair command loop.
    --@param none No arguments.
    --@return table|nil result Immutable repair outcome.
    --@return table|nil err Structured input, edit, or publication failure.
    local function run_repair()
        local written, write_error = input.write("YACA CONFIGURATION REPAIR\n"
            .. "Offline line repair; the original file stays unchanged until exact save.\n"
            .. "All source contents and replacement input are hidden. Untouched bytes are preserved.\n"
            .. "Enter help for commands. Insert adds before a line; use the last line + 1 to append.\n")
        if not written then return nil, write_error end
        local shown, show_error = show_status(1, false)
        if not shown then return nil, show_error end
        while true do
            local source, read_error = input.read(repair_id() .. "> ", false, 16384)
            if source == nil then return nil, read_error end
            if source == false then return result("cancelled", "discarded") end
            local command, action_error = runtime.cli.parse_config_repair(source, repair_id())
            local handled
            if command then
                local operation = command.operation
                if operation == "quit" or operation == "cancel" then
                    written, write_error = input.write("Unsaved repair discarded; the file was not changed.\n")
                    if not written then return nil, write_error end
                    return result(operation == "quit" and "success" or "cancelled", "discarded")
                elseif operation == "help" then
                    handled, action_error = input.write(assert(runtime.cli.render_help("config-repl")))
                elseif operation == "list" or operation == "preview" or operation == "validate" then
                    handled, action_error = show_status(command.page or 1, operation ~= "list")
                elseif operation == "reset" or operation == "reload" then
                    local replacement = base
                    if operation == "reload" then
                        replacement, action_error = config.begin_repair(composed.layout.config_path)
                    end
                    if replacement then
                        handled, action_error = advance(replacement)
                        if handled then
                            base = replacement
                            handled, action_error = show_status(1, false)
                        end
                    end
                elseif operation == "save" then
                    local status
                    status, action_error = show_status(1, true)
                    if status and not status.valid then
                        handled = true
                    elseif status then
                        local closed, close_error = input.close()
                        if not closed then return nil, close_error end
                        local committed, commit_error
                        for _ = 1, 8 do
                            local random, random_error = composed.backend.system.secure_random(12)
                            if not random then return nil, random_error end
                            committed, commit_error = config.commit_repair(draft,
                                composed.layout.config_path .. ".yaca-edit-" .. hex_bytes(random) .. ".tmp")
                            if committed then break end
                            local code = commit_error and commit_error.code
                            if code ~= "DestinationExists" and code ~= "AlreadyExists"
                                and code ~= "TemporaryConflict"
                            then
                                break
                            end
                        end
                        if committed then
                            written, write_error = input.write("Repaired configuration published offline.\n")
                            if not written then return nil, write_error end
                            return result("success", "published", committed)
                        end
                        if commit_error and commit_error.code == "ConfigPublishUnknown" then
                            return nil, commit_error
                        end
                        action_error = commit_error
                    end
                else
                    local status = assert(config.repair_status(draft))
                    local value
                    if operation ~= "delete" then
                        value, action_error = input.read("Complete replacement INI line [hidden]> ",
                            true, status.maximum_line_bytes)
                        if value == false then return result("cancelled", "discarded") end
                    end
                    if operation == "delete" or value ~= nil then
                        local replacement
                        replacement, action_error = config.edit_repair(draft, operation, command.line, value)
                        value = nil
                        if replacement then
                            handled, action_error = advance(replacement)
                            if handled then handled, action_error = show_status(1, true) end
                        end
                    end
                end
            end
            if not handled then
                if action_error and action_error.code == "BrokenStdout" then return nil, action_error end
                written, write_error = input.write("ERROR "
                    .. safe_diagnostic(action_error and action_error.code or "ConfigEditorFailure", 128)
                    .. ": repair was not applied; use list, preview, reload, or quit.\n")
                if not written then return nil, write_error end
            end
        end
    end
    local called, outcome, run_error = pcall(run_repair)
    local closed, close_error = input.close()
    if not closed then return nil, close_error end
    if not called then return nil, failure("ConfigEditorFailure", "configuration repair failed") end
    return outcome, run_error
end

---Runs one offline configuration edit with catalog-derived fields and previews.
-- Plain ASCII lines work without ANSI or cursor movement. Secret-capable INI
-- fields use the existing native raw/no-echo input and restore terminal state
-- on every outcome. Saves retain the config service's exact stale/atomic gates.
--@param composed table Runtime with config, layout, terminal, clock, and random ports.
--@param runtime table Admitted TTY invocation with shared CLI and stdout.
--@return table|nil result Saved, unchanged, discarded, or cancelled outcome.
--@return table|nil err Typed input, output, validation, or publication failure.
function M.run_config_repl(composed, runtime)
    if type(composed) ~= "table" or type(composed.config) ~= "table"
        or type(composed.layout) ~= "table" or type(composed.layout.config_path) ~= "string"
        or type(composed.backend) ~= "table" or type(composed.backend.new_terminal) ~= "function"
        or type(composed.backend.clock_port) ~= "table"
        or type(composed.backend.clock_port.monotonic_now) ~= "function"
        or type(composed.backend.clock_port.sleep_ms) ~= "function"
        or type(composed.backend.system) ~= "table"
        or type(composed.backend.system.secure_random) ~= "function"
        or type(runtime) ~= "table" or type(runtime.cli) ~= "table"
        or type(runtime.cli.parse_config_editor) ~= "function"
        or type(runtime.cli.render_help) ~= "function"
    then
        return nil, failure("InvalidConfigEditor", "configuration editor ports are incomplete")
    end
    local config = composed.config
    for _, method in ipairs({
        "begin_edit", "draft_generation", "draft_sections", "draft_fields",
        "edit_draft", "edit_draft_value", "commit_draft",
    }) do
        if type(config[method]) ~= "function" then
            return nil, failure("InvalidConfigEditor", "configuration editor service is incomplete")
        end
    end
    local base, begin_error = config.begin_edit(composed.layout.config_path)
    if not base then return nil, begin_error end
    local draft, revision = base, 1
    local changes, changed = {}, {}
    local input, input_error = new_model_setup_input(composed, runtime, "Configuration")
    if not input then return nil, input_error end
    ---Builds the revision-bound configuration editor identity.
    --@param none No arguments.
    --@return string id Current editor identity.
    local function editor_id() return "config-edit-" .. tostring(revision) end
    ---Builds the immutable configuration editor outcome.
    --@param outcome string Editor outcome.
    --@param state string Terminal editor state.
    --@param generation table|nil Published configuration generation.
    --@return table result Immutable editor result.
    local function result(outcome, state, generation)
        return readonly({
            action = "config-repl", outcome = outcome, state = state,
            config_path = composed.layout.config_path,
            config_generation = generation and generation.id or false,
            online_requests = 0,
        }, "configuration editor result")
    end
    ---Redacts registered secrets in configuration editor output.
    --@param value any Value to display.
    --@return string shown Safe diagnostic string.
    local function display(value)
        local source = tostring(value)
        for _, candidate in ipairs({ base, draft }) do
            local generation = assert(config.draft_generation(candidate))
            local hits = assert(generation.scan_registered_secrets(source))
            for _ in pairs(hits) do return "[hidden]" end
        end
        return ascii_diagnostic(source, 16384)
    end
    ---Formats one configuration field with secret and default markers.
    --@param row table Catalog-derived field row.
    --@return string value Safe displayed field value.
    local function field_value(row)
        if row.hidden then return row.configured and "[hidden; configured]" or "[hidden; default]" end
        if not row.has_value then return "(unset)" end
        local value = display(row.value)
        if type(row.value) == "string" then
            value = '"' .. value:gsub('"', '\\"') .. '"'
        end
        return value .. (row.configured and "" or " (default)")
    end
    ---Finds one catalog field in a validated draft.
    --@param candidate table Configuration draft to inspect.
    --@param section string INI section name.
    --@param key string INI field key.
    --@return table|nil row Selected field row.
    --@return table|nil err Structured unknown-field failure.
    local function selected_field(candidate, section, key)
        local fields, fields_error = config.draft_fields(candidate, section)
        if not fields then return nil, fields_error end
        for _, row in ipairs(fields) do
            if row.key == key then return row end
        end
        return nil, failure("UnknownConfigField", "config field is unknown")
    end
    ---Writes a bounded configuration action error.
    --@param err table|nil Structured action failure.
    --@return boolean|nil written Whether the message was written.
    --@return table|nil write_error Structured output failure.
    local function show_error(err)
        return input.write("ERROR " .. safe_diagnostic(err and err.code or "ConfigEditorFailure", 128)
            .. ": " .. safe_diagnostic(err and err.message or "configuration action failed", 512)
            .. (err and type(err.reason) == "string" and " (" .. safe_diagnostic(err.reason, 128) .. ")" or "")
            .. "\n")
    end
    ---Displays all changed configuration fields before exact save.
    --@param none No arguments.
    --@return boolean|nil written Whether the preview was written.
    --@return table|nil err Structured output failure.
    local function preview()
        local lines = { "CONFIG PREVIEW " .. editor_id() .. " changes=" .. tostring(#changes) }
        for _, item in ipairs(changes) do
            local before = assert(selected_field(base, item.section, item.key))
            local after = assert(selected_field(draft, item.section, item.key))
            lines[#lines + 1] = display(item.section) .. "." .. item.key
                .. ": " .. field_value(before) .. " -> " .. field_value(after)
        end
        local generation = assert(config.draft_generation(draft))
        lines[#lines + 1] = "Complete configuration: valid."
        for _, warning in ipairs(generation.warnings) do
            lines[#lines + 1] = "WARNING " .. safe_diagnostic(warning.code, 128)
        end
        lines[#lines + 1] = "Save: save " .. editor_id() .. "; reset/reload/cancel/quit discard unsaved edits."
        return input.write(table.concat(lines, "\n") .. "\n")
    end
    ---Advances the configuration editor identity after an edit.
    --@param none No arguments.
    --@return boolean|nil advanced Whether the revision advanced.
    --@return table|nil err Structured revision-limit failure.
    local function advance_revision()
        if revision == math.maxinteger then
            return nil, failure("ConfigEditorLimit", "config editor identity space is exhausted")
        end
        revision = revision + 1
        return true
    end
    ---Applies one catalog-validated field change to the private draft.
    --@param command table Parsed configuration editor command.
    --@return boolean|false|nil handled Output, cancellation, or failure.
    --@return table|nil err Structured validation or input failure.
    local function apply_change(command)
        if command.section:sub(1, 6) == "Model." then
            return nil, failure("ModelEditorRequired", "Use --model-repl to edit Model configuration")
        end
        local row, row_error = selected_field(draft, command.section, command.key)
        if not row then return nil, row_error end
        local key = command.section .. "\0" .. command.key
        if not changed[key] and #changes >= 256 then
            return nil, failure("ConfigEditorLimit", "save or discard the current 256 changed fields first")
        end
        local next_draft, edit_error
        if command.operation == "unset" then
            next_draft, edit_error = config.edit_draft(draft, {
                { section = command.section, key = command.key, value = config.unset },
            })
        else
            local hint = row.form == "text" and 'quoted INI text, e.g. "text\\nnext line"'
                or (#row.values > 0 and table.concat(row.values, "|") or row.type)
            local shown, show_error_value = input.write("Value type: " .. hint
                .. (row.hidden and "; hidden input" or "") .. ". Esc cancels the editor.\n")
            if not shown then return nil, show_error_value end
            local value, read_error = input.read("value> ", row.hidden, 16384)
            if value == false then return false, read_error end
            if value == nil then return nil, read_error end
            next_draft, edit_error = config.edit_draft_value(draft, command.section, command.key, value)
            value = nil
        end
        if not next_draft then return nil, edit_error end
        local advanced, revision_error = advance_revision()
        if not advanced then return nil, revision_error end
        draft = next_draft
        if not changed[key] then
            changed[key] = true
            changes[#changes + 1] = { section = command.section, key = command.key }
        end
        return input.write("Draft " .. editor_id() .. " validated; " .. tostring(#changes)
            .. " changed field(s). Use preview before save.\n")
    end
    ---Runs the configuration editor command loop until save or exit.
    --@param none No arguments.
    --@return table|nil result Immutable editor outcome.
    --@return table|nil err Structured editor failure.
    local function run_editor()
        local written, write_error = input.write("YACA CONFIGURATION EDITOR\n"
            .. "Configuration is valid. Edits stay in memory until an exact save command.\n"
            .. "Offline only. Enter help for commands, list for sections, or quit to leave.\n")
        if not written then return nil, write_error end
        while true do
            local source, read_error = input.read(editor_id() .. "> ", false, 16384)
            if source == false then
                written, write_error = input.write("Unsaved configuration edits discarded.\n")
                if not written then return nil, write_error end
                return result("cancelled", "cancelled")
            end
            if source == nil then return nil, read_error end
            local command, action_error = runtime.cli.parse_config_editor(source, editor_id())
            local handled = true
            if command then
                if command.operation == "quit" or command.operation == "cancel" then
                    written, write_error = input.write("Unsaved configuration edits discarded.\n")
                    if not written then return nil, write_error end
                    return result(command.operation == "quit" and "success" or "cancelled",
                        #changes == 0 and "unchanged" or "discarded")
                elseif command.operation == "help" then
                    handled, action_error = input.write(assert(runtime.cli.render_help("config-repl")))
                elseif command.operation == "list" then
                    local sections = assert(config.draft_sections(draft))
                    local first = (command.page - 1) * 32 + 1
                    if first > #sections then
                        handled, action_error = nil, failure("ConfigEditorPage", "section page is out of range")
                    else
                        local lines = { "CONFIG SECTIONS page=" .. tostring(command.page) .. " total=" .. tostring(#sections) }
                        for index = first, math.min(first + 31, #sections) do
                            lines[#lines + 1] = display(sections[index])
                        end
                        if first + 31 < #sections then lines[#lines + 1] = "Next: list " .. tostring(command.page + 1) end
                        handled, action_error = input.write(table.concat(lines, "\n") .. "\n")
                    end
                elseif command.operation == "show" then
                    local fields
                    fields, action_error = config.draft_fields(draft, command.section)
                    handled = fields ~= nil
                    if fields then
                        local lines = { "[" .. display(command.section) .. "]" }
                        if command.section:sub(1, 6) == "Model." then
                            local model = assert(config.draft_generation(draft)).models[command.section:sub(7)]
                            local endpoint = normalized_endpoint_identity(model.endpoint)
                            lines[#lines + 1] = "enabled=" .. tostring(model.enabled)
                                .. " protocol=" .. display(model.protocol)
                                .. " remote=" .. display(model.remote_model or "(unset)")
                                .. " origin=" .. (endpoint and display(endpoint.origin) or "(unset)")
                                .. " key=" .. (model.key_configured and "set" or "missing")
                            lines[#lines + 1] = "Edit Models with --model-repl."
                        else
                            for _, row in ipairs(fields) do
                                lines[#lines + 1] = row.key .. " = " .. field_value(row) .. " [" .. row.type .. "]"
                            end
                        end
                        handled, action_error = input.write(table.concat(lines, "\n") .. "\n")
                    end
                elseif command.operation == "preview" then
                    handled, action_error = preview()
                elseif command.operation == "reset" or command.operation == "reload" then
                    local replacement = base
                    if command.operation == "reload" then
                        replacement, action_error = config.begin_edit(composed.layout.config_path)
                    end
                    if replacement then
                        handled, action_error = advance_revision()
                        if handled then
                            base, draft, changes, changed = replacement, replacement, {}, {}
                            handled, action_error = input.write("Unsaved edits discarded. Current draft: " .. editor_id() .. "\n")
                        end
                    else
                        handled = nil
                    end
                elseif command.operation == "save" then
                    handled, action_error = preview()
                    if handled and #changes == 0 then return result("success", "unchanged") end
                    if handled then
                        handled, action_error = input.close()
                        if not handled then return nil, action_error end
                        local committed, commit_error
                        for _ = 1, 8 do
                            local random, random_error = composed.backend.system.secure_random(12)
                            if not random then return nil, random_error end
                            committed, commit_error = config.commit_draft(draft,
                                composed.layout.config_path .. ".yaca-edit-" .. hex_bytes(random) .. ".tmp")
                            if committed then break end
                            local code = commit_error and commit_error.code
                            if code ~= "DestinationExists" and code ~= "AlreadyExists" and code ~= "TemporaryConflict" then break end
                        end
                        if committed then
                            written, write_error = input.write("Configuration published offline. No network request was made.\n")
                            if not written then return nil, write_error end
                            return result("success", "published", committed)
                        end
                        if commit_error and commit_error.code == "ConfigPublishUnknown" then return nil, commit_error end
                        handled, action_error = nil, commit_error
                    end
                else
                    handled, action_error = apply_change(command)
                    if handled == false then
                        written, write_error = input.write("Unsaved configuration edits discarded.\n")
                        if not written then return nil, write_error end
                        return result("cancelled", "cancelled")
                    end
                end
            else
                handled = nil
            end
            if not handled then
                if action_error and action_error.code == "BrokenStdout" then return nil, action_error end
                written, write_error = show_error(action_error)
                if not written then return nil, write_error end
            end
        end
    end
    local called, outcome, run_error = pcall(run_editor)
    local closed, close_error = input.close()
    if not closed then return nil, close_error end
    if not called then return nil, failure("ConfigEditorFailure", "configuration editor failed") end
    return outcome, run_error
end

---Collects the exact workspace confirmation without opening a Context body.
--@param input table Interactive Context input/output port.
--@param preview table Verified Context continuation preview.
--@return boolean|nil accepted Whether the operator confirmed.
--@return string|table|nil confirmation Exact input or structured failure.
local function confirm_context_workspace(input, preview)
    if preview.requires_workspace_confirmation ~= true then return true end
    local written, write_error = input.write("CONTINUE " .. safe_diagnostic(preview.context_hash, 16)
        .. "\nCurrent workspace: " .. safe_diagnostic(preview.origin_workspace, 1024)
        .. "\nContext workspace: " .. safe_diagnostic(preview.recorded_workspace, 1024)
        .. "\nFuture tools use the Context workspace. History is not moved or replayed.\n")
    if not written then return nil, write_error end
    local answer, answer_error = input.read("Type CONTINUE " .. preview.context_hash .. " to confirm: ", false, 128)
    if answer == nil then return nil, answer_error end
    if answer == false then return nil, failure("ContextReplCancelled", "Context continuation was cancelled") end
    if answer ~= "CONTINUE " .. preview.context_hash then
        written, write_error = input.write("Context continuation cancelled; the workspace was not changed.\n")
        if not written then return nil, write_error end
        return false
    end
    return true, answer
end

---Prompts only for a cross-workspace CLI continuation, restoring the terminal
-- before the caller can open a writer or start the chat coordinator.
--@param composed table Production runtime composition.
--@param runtime table CLI invocation ports.
--@param preview table Verified Context continuation preview.
--@return table|nil choice Operator choice and optional confirmation.
--@return table|nil err Structured input or terminal failure.
function M.confirm_continue(composed, runtime, preview)
    if preview.requires_workspace_confirmation ~= true then return { accepted = true } end
    local input, input_error = new_model_setup_input(composed, runtime, "Context")
    if not input then return nil, input_error end
    local called, accepted, confirmation = pcall(confirm_context_workspace, input, preview)
    local closed, close_error = input.close()
    if not closed then return nil, close_error end
    if not called then return nil, failure("ContextReplFailure", "Context continuation prompt failed") end
    if accepted == nil then
        if confirmation and confirmation.code == "ContextReplCancelled" then return { accepted = false } end
        return nil, confirmation
    end
    return { accepted = accepted, confirmation = confirmation }
end

---Runs the bounded offline Context management REPL.
-- Every action resolves through the Resolver and reverifies the precise
-- TargetSnapshot before reading; catalog display rows are never used to
-- rebuild a target. Contexts held by an active writer report bounded
-- metadata only and never open the Context body. Connected mutations use a
-- short-lived exact writer; uncertain publication stops the management loop.
--@param composed table Composed runtime carrying Context services.
--@param runtime table Admitted TTY invocation with shared CLI and stdout.
--@param request table|nil Initial Context catalog request.
--@return table|nil result Bounded catalog outcome or cancellation.
--@return table|nil err Typed input, output, scan, or resolver failure.
function M.run_context_repl(composed, runtime, request)
    if type(composed) ~= "table"
        or type(composed.backend) ~= "table"
        or type(composed.backend.new_terminal) ~= "function"
        or type(composed.backend.clock_port) ~= "table"
        or type(composed.backend.clock_port.monotonic_now) ~= "function"
        or type(composed.backend.clock_port.sleep_ms) ~= "function"
        or type(runtime) ~= "table" or type(runtime.cli) ~= "table"
        or type(runtime.cli.parse_context_repl) ~= "function"
        or type(runtime.cli.render_help) ~= "function"
    then
        return nil, failure("InvalidContextRepl", "Context REPL ports are incomplete")
    end
    local contexts = composed.contexts
    if type(contexts) ~= "table" or type(contexts.catalog) ~= "table" then
        return nil, failure("ContextCatalogUnavailable", "Context catalog services are unavailable")
    end
    local input, input_error = new_model_setup_input(composed, runtime, "Context")
    if not input then return nil, input_error end

    local observation, generation = false, composed.config_generation or false
    ---Builds an immutable Context management outcome.
    --@param outcome string Management outcome.
    --@param state string Terminal manager state.
    --@param extra table|nil Additional selected Context fields.
    --@return table result Immutable Context manager result.
    local function result(outcome, state, extra)
        local value = {
            action = "context-repl", outcome = outcome, state = state,
            online_requests = 0,
        }
        for key, item in pairs(extra or {}) do value[key] = item end
        return readonly(value, "Context REPL result")
    end
    ---Writes a bounded Context action error.
    --@param err table|nil Structured action failure.
    --@return boolean|nil written Whether the message was written.
    --@return table|nil write_error Structured output failure.
    local function show_error(err)
        return input.write("ERROR " .. safe_diagnostic(err and err.code or "ContextReplFailure", 128)
            .. ": " .. safe_diagnostic(err and err.message or "Context action failed", 512)
            .. (err and type(err.next_action) == "string" and " (" .. safe_diagnostic(err.next_action, 128) .. ")" or "")
            .. "\n")
    end

    ---Re-observes the catalog; every listing reads this bounded snapshot.
    --@param none No arguments.
    --@return boolean|nil scanned Whether the catalog was observed.
    --@return table|nil err Structured catalog failure.
    local function rescan()
        local observed, observe_error = observe_context_catalog(contexts)
        if not observed then return nil, observe_error end
        observation = observed
        return true
    end

    ---Formats one bounded Context catalog row.
    --@param index integer One-based row position.
    --@param row table Observed Context metadata row.
    --@return string line Safe catalog display line.
    local function row_line(index, row)
        return string.format(
            "%2d %s [%-11s] %s - %s",
            index,
            safe_diagnostic(row.hash16, 16),
            safe_diagnostic(row.header_state, 32),
            safe_diagnostic(row.display_name, 128),
            safe_diagnostic(row.logical_path, 256)
        )
    end

    ---Writes a bounded Context catalog or search result page.
    --@param heading string Page heading.
    --@param rows table Metadata rows to show.
    --@param total integer Total matching rows.
    --@param truncated boolean Whether more rows exist.
    --@param hint string Truncation guidance.
    --@return boolean|nil written Whether the page was written.
    --@return table|nil err Structured output failure.
    local function render_rows(heading, rows, total, truncated, hint)
        local lines = { heading }
        if #rows == 0 then
            lines[#lines + 1] = "No matching Contexts were found."
        else
            for index, row in ipairs(rows) do lines[#lines + 1] = row_line(index, row) end
        end
        if truncated then lines[#lines + 1] = hint end
        lines[#lines + 1] = "Total: " .. tostring(total)
        return input.write(table.concat(lines, "\n") .. "\n")
    end

    ---Shows the requested bounded Context catalog view.
    --@param view string Catalog view identity.
    --@return boolean|nil written Whether the page was written.
    --@return table|nil err Structured output failure.
    local function list(view)
        local page = context_catalog_page(contexts, observation, generation, view)
        return render_rows(
            "CONTEXT CATALOG view=" .. view
                .. " sort=" .. safe_diagnostic(tostring(page.sort_by), 32)
                .. "/" .. safe_diagnostic(tostring(page.sort_direction), 32)
                .. (observation.complete and "" or " (scan incomplete)"),
            page.rows, page.total, page.truncated,
            view == "recent" and "More Contexts exist; use list full."
                or "Results were truncated; use search to narrow the catalog."
        )
    end

    ---Filters the current snapshot; it never rescans behind the operator.
    --@param query string Search text.
    --@return boolean|nil written Whether results were written.
    --@return table|nil err Structured output failure.
    local function search(query)
        local needle = query:lower()
        local matches, total = {}, 0
        for _, row in ipairs(observation.rows) do
            local name = tostring(row.display_name or ""):lower()
            local logical = tostring(row.logical_path or ""):lower()
            if name:find(needle, 1, true) or logical:find(needle, 1, true)
                or tostring(row.hash16 or ""):lower():find(needle, 1, true)
            then
                total = total + 1
                if #matches < CONTEXT_BROWSER_PAGE_LIMIT then matches[#matches + 1] = row end
            end
        end
        return render_rows(
            "CONTEXT SEARCH " .. ascii_diagnostic(query, 128)
                .. (observation.complete and "" or " (scan incomplete)"),
            matches, total, total > #matches,
            "Results were truncated; narrow the query."
        )
    end

    ---Resolves the selector, then reverifies the captured TargetSnapshot.
    -- The rendered row is never used to rebuild the target.
    --@param selector string Context selector.
    --@return boolean|nil written Whether metadata was written.
    --@return table|nil err Structured resolve or output failure.
    local function inspect(selector)
        local selection = contexts.catalog.resolve(selector, "/")
        if type(selection) ~= "table" or type(selection.tag) ~= "string" then
            return nil, failure("ContextResolverContract", "Context resolver returned an invalid result")
        end
        if selection.tag == "MatchedUnavailable" then
            return input.write("CONTEXT UNAVAILABLE-METADATA-ONLY " .. safe_diagnostic(selection.logical_path, 256)
                .. "\nreason: " .. safe_diagnostic(selection.reason, 128)
                .. "\nAn active writer or unreadable header blocks inspection; the body was not opened.\n")
        end
        if selection.tag ~= "Unique" then
            local detail = selection.reason or selection.scope or ""
            return nil, failure(
                "ContextSelectorUnresolved",
                "selector did not resolve to one Context",
                safe_diagnostic(tostring(selection.tag) .. (detail ~= "" and ":" .. tostring(detail) or ""), 128)
            )
        end
        local verified = contexts.catalog.verify_target(selection, "open")
        if type(verified) ~= "table" or type(verified.tag) ~= "string" then
            return nil, failure("ContextResolverContract", "Context reverification returned an invalid result")
        end
        if verified.tag ~= "Verified" then
            return nil, failure(
                verified.tag == "TargetChanged" and "ContextTargetChanged" or "ContextTargetUnavailable",
                "the selected Context could not be reverified for inspection",
                safe_diagnostic(tostring(verified.tag) .. ":" .. tostring(verified.reason or ""), 128)
            )
        end
        local credential = verified.credential
        local lines = {
            "CONTEXT " .. safe_diagnostic(verified.hash, 16),
            "logical:  " .. safe_diagnostic(verified.logical_path, 256),
            "display:  " .. safe_diagnostic(verified.display_path, 256),
            "state:    " .. safe_diagnostic(verified.header_state, 32),
            "name:     " .. safe_diagnostic(tostring(credential.canonical_name or "(none)"), 256),
            "created:  " .. safe_diagnostic(tostring(credential.created_at or "(unknown)"), 64),
            "updated:  " .. safe_diagnostic(tostring(credential.updated_at or "(unknown)"), 64),
            "verified: reverified for open immediately before this display.",
        }
        if verified.physical_hint and verified.physical_hint ~= verified.display_path then
            lines[#lines + 1] = "physical: " .. safe_diagnostic(verified.physical_hint, 256)
        end
        return input.write(table.concat(lines, "\n") .. "\n")
    end

    ---Binds one management action to the Resolver's private target snapshot.
    -- Destructive confirmation precedes a second verification of that snapshot;
    -- it never selects a replacement after the operator has seen the target.
    --@param action table Parsed Context mutation action.
    --@return boolean|nil handled Whether mutation and rescan completed.
    --@return table|nil err Structured resolve, mutation, or output failure.
    local function mutate(action)
        if type(composed.config) == "table" and type(composed.config.reload_file) == "function"
            and type(composed.layout) == "table" and type(composed.layout.config_path) == "string"
        then
            -- Offline metadata management also works with missing/invalid INI.
            -- When valid, use its current secret scanner before storing a name.
            generation = composed.config.reload_file(composed.layout.config_path) or false
        end
        local publication = composed.publication
        if type(publication) ~= "table" or type(publication.manage_context) ~= "function" then
            return nil, failure("ContextActionUnavailable", "Context mutation service is unavailable", action.id)
        end
        local deleting = action.id == "context-delete"
        local rebinding = action.id == "context-rebind"
        local repairing = action.id == "context-repair"
        local resolve = repairing and contexts.catalog.resolve_for_repair
            or (deleting and contexts.catalog.resolve_for_delete or contexts.catalog.resolve)
        if type(resolve) ~= "function" then
            return nil, failure("ContextActionUnavailable", "Context deletion resolver is unavailable")
        end
        local selection = resolve(action.selector, "/")
        if type(selection) ~= "table" or selection.tag ~= "Unique" then
            return nil, failure("ContextSelectorUnresolved", "selector did not resolve to one manageable Context",
                type(selection) == "table" and selection.tag or "resolver-contract")
        end
        local purpose = repairing and "repair" or (deleting and "delete" or "mutation")
        ---Reverifies the exact selected Context for this mutation purpose.
        --@param none No arguments.
        --@return table|nil target Verified Context target.
        --@return table|nil err Structured stale or unavailable failure.
        local function verify()
            local target = contexts.catalog.verify_target(selection, purpose)
            if type(target) ~= "table" or target.tag ~= "Verified" then
                return nil, failure(type(target) == "table" and target.tag == "TargetChanged"
                    and "ContextTargetChanged" or "ContextTargetUnavailable",
                    "the selected Context changed or is unavailable")
            end
            return target
        end
        local target, target_error = verify()
        if not target then return nil, target_error end
        local rebind_plan
        local repair_plan
        if repairing then
            if type(publication.plan_repair) ~= "function" then
                return nil, failure("ContextActionUnavailable", "read-only Context repair planning is unavailable")
            end
            repair_plan, target_error = publication.plan_repair({ context_path = target.physical_hint,
                logical_path = target.logical_path, expected_credential = target.credential })
            if not repair_plan then return nil, target_error end
            if repair_plan.action == "no-repair-needed" then
                local written, write_error = input.write("No previous-file repair is needed; no changes.\n")
                if not written then return nil, write_error end
            else
                local written, write_error = input.write("REPAIR " .. target.hash
                    .. "\nAction: " .. safe_diagnostic(repair_plan.action, 64)
                    .. "\nSource: " .. safe_diagnostic(repair_plan.source_path, 512)
                    .. "\nTarget: " .. safe_diagnostic(target.physical_hint, 512)
                    .. "\nCleanup after verified publication: " .. safe_diagnostic(repair_plan.previous_path, 512)
                    .. "\nPublishes the validated history with a repair record. No operation replay.\n")
                if not written then return nil, write_error end
                local answer, answer_error = input.read("Type REPAIR " .. target.hash .. " to confirm: ", false, 128)
                if answer == false then return nil, failure("ContextReplCancelled", "Context repair was cancelled") end
                if answer == nil then return nil, answer_error end
                if answer ~= "REPAIR " .. target.hash then
                    return input.write("Context repair cancelled; no files were changed.\n")
                end
            end
            target, target_error = verify()
            if not target then return nil, target_error end
        end
        if rebinding then
            if type(publication.plan_rebind) ~= "function" then
                return nil, failure("ContextActionUnavailable", "Context rebind planning is unavailable")
            end
            rebind_plan, target_error = publication.plan_rebind({
                context_path = target.physical_hint, logical_path = target.logical_path,
                expected_credential = target.credential, target_root = action.target_root,
            })
            if not rebind_plan then return nil, target_error end
            local written, write_error = input.write("REBIND " .. target.hash
                .. " " .. safe_diagnostic(target.logical_path, 512)
                .. "\nNew workspace: " .. safe_diagnostic(rebind_plan.target_root, 512)
                .. "\nNew Context: " .. safe_diagnostic(rebind_plan.target_hash, 16)
                .. " " .. safe_diagnostic(rebind_plan.target_logical_path, 512)
                .. "\nMoves the Context XML. Future tools use the new workspace.\n")
            if not written then return nil, write_error end
            local answer, answer_error = input.read("Type REBIND " .. target.hash .. " to confirm: ", false, 128)
            if answer == false then
                return nil, failure("ContextReplCancelled", "Context rebind was cancelled")
            end
            if answer == nil then return nil, answer_error end
            if answer ~= "REBIND " .. target.hash then
                return input.write("Context rebind cancelled; no files were changed.\n")
            end
            target, target_error = verify()
            if not target then return nil, target_error end
        end
        if deleting then
            local written, write_error = input.write("PERMANENT DELETE "
                .. safe_diagnostic(target.hash, 16) .. " " .. safe_diagnostic(target.logical_path, 512)
                .. "\nDeletes the Context XML and its known transaction files. No undo or secure erase.\n")
            if not written then return nil, write_error end
            if not action.yes then
                local answer, answer_error = input.read("Type DELETE " .. target.hash .. " to confirm: ", false, 128)
                if answer == false then
                    return nil, failure("ContextReplCancelled", "Context deletion was cancelled")
                end
                if answer == nil then return nil, answer_error end
                if answer ~= "DELETE " .. target.hash then
                    return input.write("Context deletion cancelled; no files were changed.\n")
                end
            end
            target, target_error = verify()
            if not target then return nil, target_error end
        end
        if action.id == "context-rename" and generation
            and type(generation.scan_registered_secrets) == "function"
        then
            local called, matches = pcall(generation.scan_registered_secrets, action.new_name)
            if not called or type(matches) ~= "table" then
                return nil, failure("SecretScanUnavailable", "Context name could not be checked")
            end
            if #matches > 0 then
                return nil, failure("RegisteredSecret", "Context name contains registered secret material")
            end
        end
        local receipt, mutation_error = publication.manage_context({
            action = repairing and "repair" or (deleting and "delete") or (rebinding and "rebind") or (action.id == "context-rename"
                and "rename" or "set_auto_rename_disabled"),
            context_path = target.physical_hint,
            logical_path = target.logical_path,
            expected_credential = target.credential,
            new_name = action.new_name,
            value = action.value,
            rebind_plan = rebind_plan,
            repair_plan = repair_plan,
        })
        if not receipt then return nil, mutation_error end
        local lines = {}
        if deleting then
            lines[#lines + 1] = "Context deletion: " .. safe_diagnostic(receipt.outcome, 32)
            for _, item in ipairs(receipt.targets or {}) do
                lines[#lines + 1] = safe_diagnostic(item.role, 32) .. ": "
                    .. safe_diagnostic(item.outcome, 64) .. " " .. safe_diagnostic(item.path, 512)
            end
        else
            lines[#lines + 1] = "Context " .. safe_diagnostic(receipt.outcome, 32)
                .. ": " .. safe_diagnostic(receipt.context_hash, 16)
                .. " " .. safe_diagnostic(receipt.logical_path, 512)
            if receipt.auto_rename_disabled ~= nil then
                lines[#lines + 1] = "AutoRenameDisabled=" .. tostring(receipt.auto_rename_disabled)
            end
        end
        local written, write_error = input.write(table.concat(lines, "\n") .. "\n")
        if not written then return nil, write_error end
        if deleting and receipt.outcome ~= "deleted" then
            return nil, failure("ContextMutationUnknown", "partial deletion requires inspection before more changes")
        end
        return rescan()
    end

    ---Imports only a file already placed at its intended Context mirror path.
    -- The read-only inspection, mapping preview and final writer all retain the
    -- original private selection; no catalog display row becomes authority.
    --@param action table Parsed in-place import action.
    --@return boolean|nil handled Whether import and rescan completed.
    --@return table|nil err Structured import or output failure.
    local function import_context(action)
        local publication = composed.publication
        if type(publication) ~= "table" or type(publication.plan_import) ~= "function"
            or type(publication.manage_context) ~= "function"
            or type(contexts.catalog_verifier) ~= "table"
            or type(contexts.catalog_verifier.observe) ~= "function"
            or type(contexts.store) ~= "table" or type(contexts.store.inspect_import) ~= "function"
            or type(contexts.context_root) ~= "string"
        then
            return nil, failure("ContextActionUnavailable", "in-place Context import is unavailable")
        end
        local path = contexts.path
        local platform_kind = runtime.identity and runtime.identity.os == "windows" and "windows" or "posix"
        local requested = action.path
        if not valid_absolute_path(requested) then
            local current, current_error = workspace_port(runtime.native or {}).inspect(".")
            if not current then return nil, current_error end
            requested = join_path(current.path, requested, platform_kind)
        end
        local absolute, path_error = path.to_logical(requested)
        if not absolute then return nil, path_error end
        local root, root_error = path.to_logical(contexts.context_root)
        if not root then return nil, root_error end
        if absolute == root or path.is_within_root(absolute, root, platform_kind) ~= true then
            return nil, failure("InvalidImportPath", "place the XML inside its intended Context mirror first")
        end
        local logical = absolute:sub(#root + 1)
        local details, details_error = path.context_file(logical)
        if not details then return nil, details_error end
        local physical, physical_error = path.from_logical(absolute, platform_kind)
        if not physical then return nil, physical_error end
        local observed, candidate = contexts.catalog_verifier.observe({ physical_path = physical,
            logical_path = logical })
        if not observed then return nil, candidate end
        local selection, selection_error = contexts.catalog.capture_target(candidate)
        if not selection then return nil, selection_error end
        ---Reverifies the captured in-place import target.
        --@param none No arguments.
        --@return table|nil target Verified import target.
        --@return table|nil err Structured stale or unavailable failure.
        local function verify()
            local target = contexts.catalog.verify_target(selection, "mutation")
            if type(target) ~= "table" or target.tag ~= "Verified" then
                return nil, failure(type(target) == "table" and target.tag == "TargetChanged"
                    and "ContextTargetChanged" or "ContextTargetUnavailable",
                    "the in-place Context changed or is unavailable")
            end
            return target
        end
        local target, target_error = verify()
        if not target then return nil, target_error end
        local document, report = contexts.store.inspect_import(target.physical_hint, target.credential)
        if not document then return nil, report end
        local written, write_error = input.write("VALIDATED READ-ONLY " .. target.hash
            .. " " .. safe_diagnostic(target.logical_path, 512)
            .. "\nHistorical approvals are audit-only; unfinished work will not be replayed.\n")
        if not written then return nil, write_error end
        if type(composed.config) ~= "table" or type(composed.config.reload_file) ~= "function"
            or type(composed.layout) ~= "table" or type(composed.layout.config_path) ~= "string"
        then
            return nil, failure("ConfigUnavailable", "valid local configuration is required for import mapping")
        end
        local local_generation, config_error = composed.config.reload_file(composed.layout.config_path)
        if not local_generation then return nil, config_error end
        ---Prompts for one eligible local resource mapping.
        --@param kind string Resource kind, Model or Permission.
        --@param previous string Imported resource name.
        --@param order table Ordered local resource names.
        --@param profiles table Local resources indexed by name.
        --@return string|nil selected Eligible local resource name.
        --@return table|nil err Structured input or selection failure.
        local function choose(kind, previous, order, profiles)
            local names = {}
            local previous_name = require("config").resolve_resource(local_generation, kind, previous)
            local default
            for _, name in ipairs(order) do
                local profile = profiles[name]
                if kind ~= "Model" or (profile.enabled == true and profile.tools_enabled == true) then
                    names[#names + 1] = safe_diagnostic(name, 256)
                    if name == previous_name then default = name end
                end
            end
            local shown, show_error = input.write("Local " .. kind .. ": " .. table.concat(names, ", ") .. "\n")
            if not shown then return nil, show_error end
            if #names == 0 then return nil, failure(kind .. "Unavailable", "no eligible local " .. kind) end
            local answer, answer_error = input.read(kind .. " mapping for " .. safe_diagnostic(previous, 256)
                .. (default and " [" .. safe_diagnostic(default, 256) .. "]" or "") .. ": ", false, 256)
            if answer == false then return nil, failure("ContextReplCancelled", "Context import was cancelled") end
            if answer == nil then return nil, answer_error end
            if answer == "" then answer = default end
            if answer then answer = require("config").resolve_resource(local_generation, kind, answer) end
            local selected = answer and profiles[answer]
            if not selected or (kind == "Model" and (selected.enabled ~= true or selected.tools_enabled ~= true)) then
                return nil, failure(kind .. "Unavailable", "choose an eligible local " .. kind .. " by exact name")
            end
            return answer
        end
        local model, model_error = choose("Model", document.session.current_model.name,
            local_generation.model_order, local_generation.models)
        if not model then return nil, model_error end
        local permission, permission_error = choose("Permission", document.session.current_permission.name,
            local_generation.permission_order, local_generation.permissions)
        if not permission then return nil, permission_error end
        local goal = document.session.double_check_goal_override
        local overrides = {
            CurrentModel = model, CurrentPermission = permission,
            DoubleCheckOverride = document.session.double_check_override,
            DoubleCheckGoalOverride = goal.mode == "value" and goal.value or "inherit",
            ContextPrompt = document.session.context_prompt,
            AutoRenameDisabled = document.header.auto_rename_disabled == true,
        }
        generation, config_error = composed.config.reload_file(composed.layout.config_path, overrides)
        if not generation then return nil, config_error end
        target, target_error = verify()
        if not target then return nil, target_error end
        local proposal, proposal_error = publication.plan_import({
            context_path = target.physical_hint, logical_path = target.logical_path,
            expected_credential = target.credential, generation = generation,
        })
        if not proposal then return nil, proposal_error end
        written, write_error = input.write("IMPORT " .. target.hash
            .. "\nWorkspace: " .. safe_diagnostic(proposal.workspace, 512)
            .. "\nModel: " .. safe_diagnostic(proposal.previous_model, 256) .. " -> "
                .. safe_diagnostic(proposal.model, 256)
            .. "\nPermission: " .. safe_diagnostic(proposal.previous_permission, 256) .. " -> "
                .. safe_diagnostic(proposal.permission, 256)
            .. "\nUnresolved operations/tools: " .. tostring(proposal.unresolved_operations)
                .. "/" .. tostring(proposal.unresolved_tools)
            .. "; unknown operations: " .. tostring(proposal.unknown_operations)
            .. "\nWrites local mappings into this XML. Does not start a chat or replay old approvals.\n")
        if not written then return nil, write_error end
        local answer, answer_error = input.read("Type IMPORT " .. target.hash .. " to confirm: ", false, 128)
        if answer == false then return nil, failure("ContextReplCancelled", "Context import was cancelled") end
        if answer == nil then return nil, answer_error end
        if answer ~= "IMPORT " .. target.hash then
            return input.write("Context import cancelled; no files were changed.\n")
        end
        target, target_error = verify()
        if not target then return nil, target_error end
        local current, current_error = composed.config.reload_file(composed.layout.config_path, overrides)
        if not current then return nil, current_error end
        local receipt, mutation_error = publication.manage_context({
            action = "import", context_path = target.physical_hint, logical_path = target.logical_path,
            expected_credential = target.credential, import_plan = proposal, generation = current,
        })
        if not receipt then return nil, mutation_error end
        written, write_error = input.write("Context mapped: " .. safe_diagnostic(receipt.context_hash, 16)
            .. " Model=" .. safe_diagnostic(receipt.model, 256)
            .. " Permission=" .. safe_diagnostic(receipt.permission, 256) .. "\n")
        if not written then return nil, write_error end
        return rescan()
    end

    ---Exports the selected Context as read-only Markdown.
    --@param action table Parsed Context export action.
    --@return boolean|nil written Whether Markdown was written.
    --@return table|nil err Structured export or output failure.
    local function export_context(action)
        if type(composed.application) ~= "table" or type(composed.application.dispatch) ~= "function" then
            return nil, failure("ContextActionUnavailable", "read-only Context export is unavailable")
        end
        local exported, export_error = composed.application.dispatch({ id = "export-context", selector = action.selector })
        if not exported then return nil, export_error end
        if exported.kind ~= "context-export" or exported.format ~= "markdown" or type(exported.markdown) ~= "string" then
            return nil, failure("ContextExportFailure", "Context export returned an invalid result")
        end
        return input.write(exported.markdown)
    end

    ---Previews a Context and returns a confirmed continuation selection.
    --@param action table Parsed Context selection action.
    --@return table|boolean|nil result Selection, cancellation, or failure.
    --@return table|nil err Structured preview or input failure.
    local function select_context(action)
        if type(composed.application) ~= "table" or type(composed.application.preview_continue) ~= "function"
            or type(composed.application.continue_preview) ~= "function"
        then
            return nil, failure("ContextActionUnavailable", "Context continuation is unavailable")
        end
        local preview, preview_error = composed.application.preview_continue(action.selector)
        if not preview then return nil, preview_error end
        local accepted, confirmation = confirm_context_workspace(input, preview)
        if accepted == nil then return nil, confirmation end
        if not accepted then return true end
        return result("success", "continue-selected", { preview = preview, confirmation = confirmation })
    end

    ---Runs the bounded Context manager command loop.
    --@param none No arguments.
    --@return table|nil result Immutable management or selection outcome.
    --@return table|nil err Structured manager failure.
    local function run_repl()
        local scanned, scan_error = rescan()
        if not scanned then
            return nil, scan_error
        end
        local written, write_error = input.write("YACA CONTEXT MANAGER\n"
            .. "Commands: list, inspect, search, export, select, refresh, rename, rebind, import, repair, delete, set-auto-rename-disabled.\n"
            .. "Every inspect reverifies its exact target; busy Contexts show metadata only.\n"
            .. "Enter help for commands or quit to leave.\n")
        if not written then return nil, write_error end
        written, write_error = list(request and request.view or "recent")
        if not written then return nil, write_error end
        while true do
            local source, read_error = input.read("context> ", false, 4096)
            if source == false then return result("cancelled", "cancelled") end
            if source == nil then return nil, read_error end
            local trimmed = source:gsub("^%s+", ""):gsub("%s+$", "")
            local handled, action_error = true, nil
            if trimmed == "quit" or trimmed == "exit" then
                return result("success", "closed", {
                    total = observation.total or #observation.rows,
                })
            elseif trimmed == "help" then
                handled, action_error = input.write(assert(runtime.cli.render_help("context-repl")))
            elseif trimmed == "" then
                handled = true
            else
                local request
                request, action_error = runtime.cli.parse_context_repl(trimmed)
                if request then
                    if request.id == "context-list" then
                        handled, action_error = list(request.view)
                    elseif request.id == "context-search" then
                        handled, action_error = search(request.query)
                    elseif request.id == "context-inspect" then
                        handled, action_error = inspect(request.selector)
                    elseif request.id == "context-import" then
                        handled, action_error = import_context(request)
                    elseif request.id == "context-refresh" then
                        handled, action_error = rescan()
                        if handled then
                            handled, action_error = input.write("Catalog rescanned; "
                                .. tostring(#observation.rows) .. " Context(s)"
                                .. (observation.complete and "." or "; scan incomplete.") .. "\n")
                        end
                    elseif request.id == "context-rename" or request.id == "context-delete"
                        or request.id == "context-set-auto-rename-disabled" or request.id == "context-rebind"
                        or request.id == "context-repair"
                    then
                        handled, action_error = mutate(request)
                    elseif request.id == "export-context" then
                        handled, action_error = export_context(request)
                    elseif request.id == "select-context" then
                        handled, action_error = select_context(request)
                        if type(handled) == "table" and handled.state == "continue-selected" then return handled end
                    else
                        handled, action_error = nil, failure(
                            "ContextActionUnavailable",
                            "unknown Context action",
                            safe_diagnostic(tostring(request.id), 64)
                        )
                    end
                else
                    handled = false
                end
            end
            if not handled then
                if action_error and action_error.code == "ContextReplCancelled" then
                    return result("cancelled", "cancelled")
                end
                if action_error and (action_error.code == "BrokenStdout"
                    or action_error.code == "ContextMutationUnknown")
                then
                    return nil, action_error
                end
                written, write_error = show_error(action_error)
                if not written then return nil, write_error end
            end
        end
    end
    local called, outcome, run_error = pcall(run_repl)
    local closed, close_error = input.close()
    if not closed then return nil, close_error end
    if not called then return nil, failure("ContextReplFailure", "Context manager failed") end
    return outcome, run_error
end

---Renders self-test checks and outcomes for text or machine output.
--@param cli_service table CLI serialization service.
--@param request table Parsed self-test request.
--@param result table Self-test dispatch result.
--@return string output Serialized self-test report.
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

---Renders offline management summaries for non-interactive dispatch.
--@param request table Parsed management request.
--@param result table Management dispatch result.
--@return string output Safe management summary.
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

---Renders one non-interactive runtime dispatch result.
--@param cli_service table CLI rendering service.
--@param request table Parsed runtime request.
--@param result table Runtime dispatch result.
--@return string|nil output Text or machine output.
--@return table|nil err Structured interactive-only failure.
local function render_runtime_result(cli_service, request, result)
    if request.id == "self-test" then return render_self_test(cli_service, request, result) end
    if request.id == "export-context" then return result.markdown end
    if request.id == "status" then
        local lines = {
            "yaca " .. ascii_diagnostic(result.version, 64)
                .. " (" .. ascii_diagnostic(result.release_target, 64) .. ")",
            "state: " .. ascii_diagnostic(result.state, 64),
        }
        for _, line in ipairs(session_status_lines(result, ascii_diagnostic)) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = "agent ready: " .. tostring(result.agent_ready)
        return table.concat(lines, "\n") .. "\n"
    end
    if BOOTSTRAP_ACTIONS[request.id] then return render_management(request, result) end
    return nil, failure(
        "InteractiveDispatchRequired",
        "run-chat must be owned by the terminal ApplicationCoordinator"
    )
end

---Composes and dispatches a production CLI request through its owning surface.
--@param request table Parsed CLI request.
--@param runtime table Admitted CLI invocation and platform ports.
--@return table|nil result Output and optional exit value.
--@return table|nil err Structured composition or dispatch failure.
default_runtime_dispatch = function(request, runtime)
    local composed, composition_error = M.compose_runtime(runtime)
    if not composed then return nil, composition_error end
    local result, dispatch_error
    if request.id == "continue" then
        local preview, preview_error = composed.application.preview_continue(request.selector)
        if not preview then return nil, preview_error end
        local choice, choice_error = M.confirm_continue(composed, runtime, preview)
        if not choice then return nil, choice_error end
        if not choice.accepted then return { output = "" } end
        result, dispatch_error = composed.application.continue_preview(preview, choice.confirmation)
    else
        result, dispatch_error = composed.application.dispatch(request)
    end
    if not result and request.id == "run-chat"
        and dispatch_error and dispatch_error.code == "ConfigMissing"
    then
        local configured, setup_error = M.run_model_repl(composed, runtime)
        if not configured then return nil, setup_error end
        if configured.outcome ~= "success" then
            return { output = "", exit_value = configured }
        end
        -- The wizard has closed its terminal and atomically published the
        -- configuration. Recompose so the chat uses only the saved generation.
        composed, composition_error = M.compose_runtime(runtime)
        if not composed then return nil, composition_error end
        result, dispatch_error = composed.application.dispatch(request)
    end
    if not result then return nil, dispatch_error end
    if request.id == "model-repl" then
        local configured, setup_error = M.run_model_repl(composed, runtime)
        if not configured then return nil, setup_error end
        return {
            output = "",
            exit_value = configured.outcome == "success" and nil or configured,
        }
    end
    if request.id == "config-repl" and result.state == "valid" then
        local configured, editor_error = M.run_config_repl(composed, runtime)
        if not configured then return nil, editor_error end
        return { output = "", exit_value = configured.outcome == "success" and nil or configured }
    end
    if request.id == "config-repl" and result.state == "invalid" then
        local repaired, repair_error = M.run_config_repair(composed, runtime)
        if not repaired then return nil, repair_error end
        return { output = "", exit_value = repaired.outcome == "success" and nil or repaired }
    end
    if request.id == "context-repl"
        and (result.state == "catalog-ready" or result.state == "scan-incomplete")
    then
        local managed, manager_error = M.run_context_repl(composed, runtime, request)
        if not managed then return nil, manager_error end
        if managed.state ~= "continue-selected" then
            return { output = "", exit_value = managed.outcome == "success" and nil or managed }
        end
        result, dispatch_error = composed.application.continue_preview(managed.preview, managed.confirmation)
        if not result then return nil, dispatch_error end
        request = { id = "continue", selector = managed.preview.context_hash }
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
