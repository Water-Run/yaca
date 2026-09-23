--[[
Author: WaterRun
Date: 2026-09-23
File: manifest_test.lua
Description: Verifies release manifest and secure loader invariants.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
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
            --Verifies module and target allowlists match machine contracts.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify module and target allowlists match machine contracts.
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
            --Verifies module and target allowlists match machine contracts.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify module and target allowlists match machine contracts.
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
            --Verifies loader ignores ambient Lua search paths.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify loader ignores ambient Lua search paths.
            run = function()
                local valid, validation_error = loader.validate_manifest(manifest)
                A.truthy(valid, validation_error)
                local observed = {}
                local secure, loader_error = loader.new(manifest, YACA_TEST_ROOT, {
                    --Supplies the loadfile behavior used by the 'loader ignores ambient Lua search paths' case.
                    --@param path string File or Context path exercised by the case.
                    --@param mode string Operating mode selected by the scenario.
                    --@param environment any The environment supplied to the fake service for this scenario.
                    --@return function callback Nested callback supplied by this scenario.
                    loadfile = function(path, mode, environment)
                        observed.path, observed.mode, observed.environment = path, mode, environment
                        --Supplies an assertion callback for the loader ignores ambient Lua search paths scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
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
            --Verifies loader rejects traversal unknown modules and relative roots.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify loader rejects traversal unknown modules and relative roots.
            run = function()
                local relative, relative_error = loader.new(manifest, ".")
                A.falsy(relative)
                A.contains(relative_error, "absolute path")
                local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
                    --Supplies the loadfile behavior used by the 'loader rejects traversal unknown modules and relative roots' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return function callback Nested callback supplied by this scenario.
                    loadfile = function()
                        --Supplies an assertion callback for the loader rejects traversal unknown modules and relative roots scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        return function() return true end end,
                }))
                --Executes the action expected to raise in the 'loader rejects traversal unknown modules and relative roots' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function() secure:require_lua("../main") end, "not allowlisted")
                --Executes the action expected to raise in the 'loader rejects traversal unknown modules and relative roots' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function() secure:require_lua("plugin") end, "not allowlisted")
                local native_path, native_error = secure:resolve_native("plugin", "linux-x86_64")
                A.falsy(native_path)
                A.contains(native_error, "not allowlisted")
            end,
        },
        {
            name = "loader resolves native modules by explicit target only",
            --Verifies loader rejects traversal unknown modules and relative roots.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify loader rejects traversal unknown modules and relative roots.
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
            --Verifies loader resolves native modules by explicit target only.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify loader resolves native modules by explicit target only.
            run = function()
                local observed = {}
                local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
                    target_id = "linux-x86_64",
                    --Supplies the loadlib behavior used by the 'native require ignores ambient cpath and uses an absolute target path' case.
                    --@param path string File or Context path exercised by the case.
                    --@param symbol any The symbol supplied to the fake service for this scenario.
                    --@return function callback Nested callback supplied by this scenario.
                    loadlib = function(path, symbol)
                        observed.path, observed.symbol = path, symbol
                        --Supplies an assertion callback for the native require ignores ambient cpath and uses an absolute target path scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
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
                --Executes the action expected to raise in the 'native require ignores ambient cpath and uses an absolute target path' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function()
                    assert(loader.new(manifest, YACA_TEST_ROOT)):require("lxp")
                end, "explicit release target")
            end,
        },
        {
            name = "manifest validation rejects mutable code directory layouts",
            --Verifies manifest validation rejects mutable code directory layouts.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify manifest validation rejects mutable code directory layouts.
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
            --Verifies manifest validation rejects mutable code directory layouts.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify manifest validation rejects mutable code directory layouts.
            run = function()
                local mutable = {}
                for key, value in pairs(manifest) do mutable[key] = value end
                mutable.layout = {
                    lua_directory = manifest.layout.lua_directory,
                    native_directory = manifest.layout.native_directory,
                }
                local secure = assert(loader.new(mutable, YACA_TEST_ROOT, {
                    --Supplies the loadfile behavior used by the 'loader snapshots validated layout against later mutation' case.
                    --@param path string File or Context path exercised by the case.
                    --@return function callback Nested callback supplied by this scenario.
                    loadfile = function(path)
                        --Supplies an assertion callback for the loader snapshots validated layout against later mutation scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return any value Callback value consumed by the enclosing scenario assertion.
                        return function() return path end end,
                }))
                mutable.layout.lua_directory = "../malicious"
                A.equal(secure:resolve_lua("main"), YACA_TEST_ROOT .. "/src/main.lua")
            end,
        },
    },
}
