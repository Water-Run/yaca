local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_table(relative_path)
  local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
  A.truthy(chunk, load_error)
  local ok, value = pcall(chunk)
  A.truthy(ok, value)
  A.type(value, "table")
  return value
end

local manifest = load_table("release/manifest.lua")
local release_contract = load_table(".develope-docs/contracts/release.lua")
local platform_contract = load_table(".develope-docs/contracts/platform.lua")
local loader = load_table(".tools/check_loader.lua")

return {
  name = "self/manifest",
  cases = {
    {
      name = "module and target allowlists match machine contracts",
      run = function()
        A.deep_equal(manifest.lua_modules, release_contract.planned_lua_modules)
        A.deep_equal(manifest.lua_modules, platform_contract.safe_loading.lua_module_allowlist)
        A.deep_equal(manifest.native_modules, platform_contract.safe_loading.native_module_allowlist)
        local target_ids = {}
        for _, target in ipairs(manifest.targets) do
          target_ids[#target_ids + 1] = target.id
          A.equal(target.qualification, "pending")
        end
        A.deep_equal(target_ids, release_contract.packaging.targets)
        A.falsy(manifest.release_authorized)
        A.equal(manifest.release_state, "unqualified")
      end,
    },
    {
      name = "dependency pins and candidates match release contract",
      run = function()
        for _, name in ipairs({ "lua", "expat", "luaexpat" }) do
          A.equal(manifest.dependencies[name].version, release_contract.dependency_lock[name].version)
          A.equal(manifest.dependencies[name].sha256, release_contract.dependency_lock[name].sha256)
        end
        A.equal(manifest.dependencies.luainstaller.version, release_contract.packaging.luainstaller.version)
        A.equal(manifest.dependencies.luainstaller.commit, release_contract.packaging.luainstaller.commit)
        A.deep_equal(manifest.implementation_candidates.retry, release_contract.implementation_candidates.retry)
        A.equal(manifest.implementation_candidates.minimum_scannable_secret_bytes, release_contract.implementation_candidates.minimum_scannable_secret_bytes)
        A.deep_equal(manifest.unresolved_release_constants, release_contract.unresolved_release_constants)
      end,
    },
    {
      name = "loader ignores ambient Lua search paths",
      run = function()
        local valid, validation_error = loader.validate_manifest(manifest)
        A.truthy(valid, validation_error)
        local observed = {}
        local secure, loader_error = loader.new(manifest, YACA_TEST_ROOT, {
          loadfile = function(path, mode, environment)
            observed.path, observed.mode, observed.environment = path, mode, environment
            return function() return { origin = path } end
          end,
        })
        A.truthy(secure, loader_error)
        local old_path, old_cpath = package.path, package.cpath
        package.path, package.cpath = "./malicious/?.lua", "./malicious/?.so"
        local loaded = secure:require_lua("main")
        package.path, package.cpath = old_path, old_cpath
        A.equal(observed.path, YACA_TEST_ROOT .. "/src/main.lua")
        A.equal(observed.mode, "t")
        A.equal(loaded.origin, observed.path)
        A.type(observed.environment.require, "function")
      end,
    },
    {
      name = "loader rejects traversal unknown modules and relative roots",
      run = function()
        local relative, relative_error = loader.new(manifest, ".")
        A.falsy(relative)
        A.contains(relative_error, "absolute path")
        local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
          loadfile = function() return function() return true end end,
        }))
        A.raises(function() secure:require_lua("../main") end, "not allowlisted")
        A.raises(function() secure:require_lua("plugin") end, "not allowlisted")
        local native_path, native_error = secure:resolve_native("plugin", "linux-x86_64")
        A.falsy(native_path)
        A.contains(native_error, "not allowlisted")
      end,
    },
    {
      name = "loader resolves native modules by explicit target only",
      run = function()
        local secure = assert(loader.new(manifest, YACA_TEST_ROOT))
        A.equal(secure:resolve_native("lxp", "win32-x86"), YACA_TEST_ROOT .. "/native/lxp.dll")
        A.equal(secure:resolve_native("lxp", "linux-x86_64"), YACA_TEST_ROOT .. "/native/lxp.so")
        local path, resolution_error = secure:resolve_native("lxp", "unknown")
        A.falsy(path)
        A.contains(resolution_error, "unknown release target")
      end,
    },
    {
      name = "native require ignores ambient cpath and uses an absolute target path",
      run = function()
        local observed = {}
        local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
          target_id = "linux-x86_64",
          loadlib = function(path, symbol)
            observed.path, observed.symbol = path, symbol
            return function() return { native = true } end
          end,
        }))
        local old_cpath = package.cpath
        package.cpath = "./malicious/?.so"
        local loaded = secure:require("lxp")
        package.cpath = old_cpath
        A.truthy(loaded.native)
        A.equal(observed.path, YACA_TEST_ROOT .. "/native/lxp.so")
        A.equal(observed.symbol, "luaopen_lxp")
        A.equal(secure:require("lxp"), loaded)
        A.raises(function()
          assert(loader.new(manifest, YACA_TEST_ROOT)):require("lxp")
        end, "explicit release target")
      end,
    },
    {
      name = "manifest validation rejects mutable code directory layouts",
      run = function()
        local altered = {}
        for key, value in pairs(manifest) do altered[key] = value end
        altered.layout = { lua_directory = "../plugin", native_directory = "native" }
        local valid, validation_error = loader.validate_manifest(altered)
        A.falsy(valid)
        A.contains(validation_error, "fixed src/native")
      end,
    },
    {
      name = "loader snapshots validated layout against later mutation",
      run = function()
        local mutable = {}
        for key, value in pairs(manifest) do mutable[key] = value end
        mutable.layout = {
          lua_directory = manifest.layout.lua_directory,
          native_directory = manifest.layout.native_directory,
        }
        local secure = assert(loader.new(mutable, YACA_TEST_ROOT, {
          loadfile = function(path) return function() return path end end,
        }))
        mutable.layout.lua_directory = "../malicious"
        A.equal(secure:resolve_lua("main"), YACA_TEST_ROOT .. "/src/main.lua")
      end,
    },
  },
}
