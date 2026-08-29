--[[
File: check_loader.lua
Date: 2026-08-29
Author: WaterRun
Description: Validates and constructs the manifest-only secure module loader.
]]

local M = {}

local function normalize(path)
    path = tostring(path or ""):gsub("\\", "/")
    path = path:gsub("/%./", "/"):gsub("/%.$", "")
    if #path > 1 and not path:match("^[A-Za-z]:/$") then path = path:gsub("/$", "") end
    return path
end

local function is_absolute(path)
    path = normalize(path)
    return path:sub(1, 1) == "/" or path:match("^[A-Za-z]:/") ~= nil or path:match("^//[^/]+/[^/]+") ~= nil
end

local function as_set(values, label)
    if type(values) ~= "table" then return nil, label .. " must be a table" end
    local result = {}
    for index, value in ipairs(values) do
        if type(value) ~= "string" or not value:match("^[a-z][a-z0-9_]*$") then
            return nil, string.format("%s[%d] is not a canonical module name", label, index)
        end
        if result[value] then return nil, label .. " repeats " .. value end
        result[value] = true
    end
    return result
end

--- Validates the security-relevant release manifest fields.
-- @param manifest table Candidate manifest.
-- @return boolean|nil True when valid.
-- @return string|nil Validation error.
function M.validate_manifest(manifest)
    if type(manifest) ~= "table" then return nil, "manifest must be a table" end
    if manifest.schema_version ~= "yaca-release-manifest-v0.1.0" then return nil, "unexpected manifest schema" end
    if manifest.release_authorized ~= false or manifest.release_state ~= "unqualified" then
        return nil, "pre-qualification manifest must not authorize release"
    end
    local lua_set, lua_error = as_set(manifest.lua_modules, "lua_modules")
    if not lua_set then return nil, lua_error end
    local native_set, native_error = as_set(manifest.native_modules, "native_modules")
    if not native_set then return nil, native_error end
    if #manifest.lua_modules ~= 28 then return nil, "manifest must list exactly 28 Lua modules" end
    if #manifest.native_modules ~= 2 or not native_set.yaca_native or not native_set.lxp then
        return nil, "manifest must list yaca_native and lxp only"
    end
    if not lua_set.main then return nil, "manifest omits main entry module" end
    if type(manifest.layout) ~= "table" or manifest.layout.lua_directory ~= "src" or manifest.layout.native_directory ~= "native" then
        return nil, "manifest code layout must be the fixed src/native directories"
    end
    local policy = manifest.load_policy
    if type(policy) ~= "table" or policy.source ~= "absolute-release-root-only" then return nil, "manifest has no absolute load policy" end
    for _, key in ipairs({
        "current_working_directory", "lua_path", "lua_cpath", "lua_init",
        "user_directories", "system_directories", "dynamic_extension_discovery",
    }) do
        if policy[key] ~= false then return nil, "unsafe load policy: " .. key end
    end
    local target_ids = {}
    local target_count = 0
    for _, target in ipairs(manifest.targets or {}) do
        if target_ids[target.id] then return nil, "duplicate target " .. tostring(target.id) end
        target_ids[target.id] = true
        target_count = target_count + 1
        if target.qualification ~= "pending" then return nil, "target is falsely qualified: " .. tostring(target.id) end
        local filenames = manifest.native_module_filenames and manifest.native_module_filenames[target.id]
        if type(filenames) ~= "table" then return nil, "target has no native filename map: " .. tostring(target.id) end
        for name in pairs(native_set) do
            if type(filenames[name]) ~= "string" or filenames[name]:find("[/\\]") then
                return nil, "invalid native filename for " .. tostring(target.id) .. "/" .. name
            end
        end
    end
    for _, expected in ipairs({ "win32-x86", "win64-x86_64", "linux-x86_64" }) do
        if not target_ids[expected] then return nil, "manifest omits target " .. expected end
    end
    if target_count ~= 3 then return nil, "manifest must list exactly three release targets" end
    return true
end

--- Constructs a loader that uses only absolute allowlisted paths.
-- @param manifest table Validated release manifest.
-- @param release_root string Normalized absolute release root.
-- @param options table|nil Injected load functions and target identity.
-- @return table|nil Secure loader.
-- @return string|nil Construction error.
function M.new(manifest, release_root, options)
    local valid, validation_error = M.validate_manifest(manifest)
    if not valid then return nil, validation_error end
    release_root = normalize(release_root)
    local has_dot_segment = release_root:find("/../", 1, true)
        or release_root:find("/./", 1, true)
        or release_root:sub(-3) == "/.."
        or release_root:sub(-2) == "/."
    if release_root:find("\0", 1, true) or has_dot_segment or not is_absolute(release_root) then
        return nil, "release root must be a normalized absolute path without NUL or dot segments"
    end
    options = options or {}
    local loadfile_function = options.loadfile or loadfile
    local loadlib_function = options.loadlib or (package and package.loadlib)
    local base_environment = options.environment or _G
    local target_id = options.target_id
    local lua_directory = manifest.layout.lua_directory
    local native_directory = manifest.layout.native_directory
    local native_filenames = {}
    for manifest_target, filenames in pairs(manifest.native_module_filenames) do
        native_filenames[manifest_target] = {}
        for name, filename in pairs(filenames) do native_filenames[manifest_target][name] = filename end
    end
    if target_id ~= nil and not native_filenames[target_id] then return nil, "unknown release target: " .. tostring(target_id) end
    local lua_allowed = assert(as_set(manifest.lua_modules, "lua_modules"))
    local native_allowed = assert(as_set(manifest.native_modules, "native_modules"))
    local loaded, loading = {}, {}
    local loaded_present = {}
    local loader = {}
    local root_prefix = release_root:sub(-1) == "/" and release_root or release_root .. "/"

    --- Resolves an allowlisted Lua module.
    -- @param name string Canonical module name.
    -- @return string|nil Absolute source path.
    -- @return string|nil Resolution error.
    function loader:resolve_lua(name)
        if type(name) ~= "string" or not lua_allowed[name] then return nil, "module is not allowlisted: " .. tostring(name) end
        return root_prefix .. lua_directory .. "/" .. name .. ".lua"
    end

    --- Resolves an allowlisted native module for one target.
    -- @param name string Canonical native module name.
    -- @param target_id string Release target ID.
    -- @return string|nil Absolute native path.
    -- @return string|nil Resolution error.
    function loader:resolve_native(name, target_id)
        if type(name) ~= "string" or not native_allowed[name] then return nil, "native module is not allowlisted: " .. tostring(name) end
        local target = native_filenames[target_id]
        if not target then return nil, "unknown release target: " .. tostring(target_id) end
        return root_prefix .. native_directory .. "/" .. target[name]
    end

    --- Loads and caches an allowlisted Lua module.
    -- @param name string Canonical module name.
    -- @return any Module return value.
    function loader:require_lua(name)
        if loaded_present[name] then return loaded[name] end
        local path, path_error = self:resolve_lua(name)
        if not path then error(path_error, 2) end
        if loading[name] then error("cyclic secure module load: " .. name, 2) end
        loading[name] = true
        local environment = { require = function(dependency) return self:require(dependency) end }
        environment._G = environment
        setmetatable(environment, { __index = base_environment })
        local chunk, load_error = loadfile_function(path, "t", environment)
        if not chunk then
            loading[name] = nil
            error("cannot load allowlisted module " .. name .. ": " .. tostring(load_error), 2)
        end
        local ok, value = xpcall(chunk, function(message) return debug.traceback(tostring(message), 2) end)
        loading[name] = nil
        if not ok then error("allowlisted module " .. name .. " failed: " .. tostring(value), 2) end
        if value == nil then value = true end
        loaded[name], loaded_present[name] = value, true
        return value
    end

    --- Loads and caches an allowlisted native module.
    -- @param name string Canonical native module name.
    -- @param target_id string Release target ID.
    -- @return any Module return value.
    -- @return string|nil Native loading error.
    function loader:load_native(name, target_id)
        local cache_key = "native:" .. tostring(target_id) .. ":" .. tostring(name)
        if loaded_present[cache_key] then return loaded[cache_key] end
        local path, path_error = self:resolve_native(name, target_id)
        if not path then return nil, path_error end
        if type(loadlib_function) ~= "function" then return nil, "native load function is unavailable" end
        local open_symbol = "luaopen_" .. name
        local open_function, load_error = loadlib_function(path, open_symbol)
        if not open_function then return nil, tostring(load_error) end
        local value = open_function()
        if value == nil then value = true end
        loaded[cache_key], loaded_present[cache_key] = value, true
        return value
    end

    --- Loads an allowlisted Lua or native module.
    -- @param name string Canonical module name.
    -- @return any Module return value.
    function loader:require(name)
        if lua_allowed[name] then return self:require_lua(name) end
        if native_allowed[name] then
            if not target_id then error("native module requires an explicit release target: " .. name, 2) end
            local value, native_error = self:load_native(name, target_id)
            if value == nil then error("cannot load allowlisted native module " .. name .. ": " .. tostring(native_error), 2) end
            return value
        end
        error("module is not allowlisted: " .. tostring(name), 2)
    end

    return loader
end

local function root_from_script(script)
    local normalized = normalize(script)
    local root = normalized:match("^(.*)/%.tools/check_loader%.lua$")
    if not root or root == "" then root = "." end
    if is_absolute(root) then return root end
    local pipe = io.popen(package.config:sub(1, 1) == "\\" and "cd" or "pwd", "r")
    local cwd = pipe and pipe:read("l") or os.getenv("PWD")
    if pipe then pipe:close() end
    return normalize(tostring(cwd) .. "/" .. root)
end

--- Runs manifest and path validation as a command-line tool.
-- @param arguments table Lua argument array.
-- @return integer Stable process exit code.
function M.main(arguments)
    local root = root_from_script(arguments[0] or ".tools/check_loader.lua")
    local manifest_chunk, load_error = loadfile(root .. "/release/manifest.lua", "t", {})
    if not manifest_chunk then
        io.stderr:write("loader validation FAILED: ", tostring(load_error), "\n")
        return 1
    end
    local ok, manifest = pcall(manifest_chunk)
    if not ok then
        io.stderr:write("loader validation FAILED: ", tostring(manifest), "\n")
        return 1
    end
    local valid, validation_error = M.validate_manifest(manifest)
    if not valid then
        io.stderr:write("loader validation FAILED: ", tostring(validation_error), "\n")
        return 1
    end
    local loader, loader_error = M.new(manifest, root)
    if not loader then
        io.stderr:write("loader validation FAILED: ", tostring(loader_error), "\n")
        return 1
    end
    for _, name in ipairs(manifest.lua_modules) do
        local path, path_error = loader:resolve_lua(name)
        if not path or path_error or path ~= root .. "/src/" .. name .. ".lua" then
            io.stderr:write("loader validation FAILED: unsafe resolution for ", name, "\n")
            return 1
        end
    end
    io.stdout:write(string.format("loader validation PASS: %d Lua modules, %d native modules\n", #manifest.lua_modules, #manifest.native_modules))
    return 0
end

local invoked_path = type(arg) == "table" and type(arg[0]) == "string" and normalize(arg[0]) or ""
local invoked_as_tool = invoked_path == ".tools/check_loader.lua" or invoked_path:match("/%.tools/check_loader%.lua$") ~= nil
if invoked_as_tool then os.exit(M.main(arg), true) end
return M
