--[[
File: package_layout_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies exact minimal candidate package assembly policy.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_value(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    local ok, value = pcall(chunk)
    A.truthy(ok, value)
    return value
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

local manifest = load_value("release/manifest.lua")
local lock = load_value("release/dependencies.lock")
local module = load_value("release/luainstaller.lua")
local planner = assert(module.new(manifest, lock))

local TARGETS = {
    ["win32-x86"] = {
        object_format = "PE32-i386",
        executable = "yaca.exe",
        installer = "Install.cmd",
        curl = "curl.exe",
        archive = "yaca-0.1.0-win32-x86.zip",
        root = { "yaca.exe", "Install.cmd", "README.txt", "LICENSE", "docs/" },
    },
    ["win64-x86_64"] = {
        object_format = "PE32+-x86-64",
        executable = "yaca.exe",
        installer = "Install.cmd",
        curl = "curl.exe",
        archive = "yaca-0.1.0-win64-x86_64.zip",
        root = { "yaca.exe", "Install.cmd", "README.txt", "LICENSE", "docs/" },
    },
    ["linux-x86_64"] = {
        object_format = "ELF64-x86-64",
        executable = "yaca",
        installer = "Install.sh",
        curl = "curl",
        archive = "yaca-0.1.0-linux-x86_64.zip",
        root = { "yaca", "Install.sh", "README.txt", "LICENSE", "docs/" },
    },
}

local function hash(byte)
    return string.rep(byte, 64)
end

local function artifact(target_id, role, version, digest)
    local target = assert(TARGETS[target_id])
    local suffixes = {
        launcher = target.executable,
        yaca_native = target_id:match("^linux") and "yaca_native.so" or "yaca_native.dll",
        lxp = target_id:match("^linux") and "lxp.so" or "lxp.dll",
        curl = target.curl,
    }
    return {
        source_path = "build/candidates/" .. target_id .. "/" .. suffixes[role],
        sha256 = digest,
        target_id = target_id,
        object_format = target.object_format,
        lua_abi = role == "curl" and nil or "5.5",
        version = version,
        qualification = "pending",
        compression = "none",
        non_system_runtime_dependencies = {},
    }
end

local function package_file(target_id, source_name, destination, digest)
    return {
        source_path = "build/package-inputs/" .. target_id .. "/" .. source_name,
        destination_path = destination,
        sha256 = digest,
        qualification = "pending",
    }
end

local function inputs(target_id)
    local target = assert(TARGETS[target_id])
    local launcher = artifact(target_id, "launcher", "0.1.0", hash("1"))
    launcher.builder_version = "1.3.0"
    launcher.builder_commit = "97192d100077b31b61dc8f94427e14df1c68a9eb"
    launcher.mode = "onefile"
    launcher.upx = false
    local curl = artifact(target_id, "curl", "8.21.0", hash("4"))
    curl.tls_backend = "mbedtls-3.6.7"
    curl.protocols = { "http", "https" }
    curl.ca_bundle_sha256 = lock.components["ca-bundle"].sha256
    curl.upx = false
    return {
        source_revision = "0123456789abcdef0123456789abcdef01234567",
        artifacts = {
            launcher = launcher,
            yaca_native = artifact(target_id, "yaca_native", "0.1.0", hash("2")),
            lxp = artifact(target_id, "lxp", "1.5.2", hash("3")),
            curl = curl,
            ca_bundle = {
                source_path = "build/sources/cacert-2026-08-13.pem",
                sha256 = lock.components["ca-bundle"].sha256,
                target_id = "all",
                object_format = "PEM",
                version = "2026-08-13",
                qualification = "pending",
                compression = "none",
                non_system_runtime_dependencies = {},
            },
        },
        package_files = {
            installer = package_file(
                target_id,
                target.installer,
                target.installer,
                hash("5")
            ),
            readme = package_file(target_id, "README.txt", "README.txt", hash("6")),
            license = package_file(target_id, "LICENSE", "LICENSE", hash("7")),
            documents = {
                package_file(target_id, "USAGE.txt", "docs/USAGE.txt", hash("8")),
                package_file(
                    target_id,
                    "THIRD_PARTY_NOTICES.txt",
                    "docs/THIRD_PARTY_NOTICES.txt",
                    hash("9")
                ),
                package_file(target_id, "SBOM.spdx.json", "docs/SBOM.spdx.json", hash("a")),
            },
        },
    }
end

return {
    name = "release/package-layout",
    cases = {
        {
            name = "three targets have exact independent archive roots",
            run = function()
                A.deep_equal(planner.target_order, {
                    "win32-x86", "win64-x86_64", "linux-x86_64",
                })
                for target_id, expected in pairs(TARGETS) do
                    local plan = assert(planner.plan(target_id, inputs(target_id)))
                    A.equal(plan.archive, expected.archive)
                    A.deep_equal(plan.root_entries, expected.root)
                    A.equal(plan.package_files[1].destination_path, expected.executable)
                    A.equal(plan.package_files[2].destination_path, expected.installer)
                    A.equal(plan.package_files[3].destination_path, "README.txt")
                    A.equal(plan.package_files[4].destination_path, "LICENSE")
                    A.equal(#plan.outer_runtime_components, 0)
                    A.equal(plan.status, "candidate-unqualified")
                    A.falsy(plan.release_authorized)
                    A.falsy(plan.target_qualification_complete)
                end
            end,
        },
        {
            name = "onedir prerequisite and onefile payload are explicit and minimal",
            run = function()
                local plan = assert(planner.plan("linux-x86_64", inputs("linux-x86_64")))
                A.equal(plan.luainstaller.version, "1.3.0")
                A.equal(
                    plan.luainstaller.commit,
                    "97192d100077b31b61dc8f94427e14df1c68a9eb"
                )
                A.deep_equal(
                    plan.luainstaller.downstream_patches,
                    lock.components.luainstaller.downstream_patches
                )
                A.equal(
                    plan.luainstaller.downstream_patches[1].sha256,
                    "df011b4a5f54e96a098a2dd235e6a7dc300f7ed7ff7e2a2c269b9b01ff203210"
                )
                A.equal(plan.luainstaller.prerequisite_mode, "onedir")
                A.equal(plan.luainstaller.final_mode, "onefile")
                A.equal(plan.luainstaller.discovery_mode, "manual")
                A.deep_equal(plan.luainstaller.lua_modules, manifest.lua_modules)
                A.deep_equal(plan.luainstaller.native_modules, { "yaca_native", "lxp" })
                A.deep_equal(plan.inner_payload, {
                    {
                        role = "yaca_native",
                        source_path = "build/candidates/linux-x86_64/yaca_native.so",
                        destination_path = ".luai/native/yaca_native.so",
                        sha256 = hash("2"),
                        qualification = "pending",
                    },
                    {
                        role = "lxp",
                        source_path = "build/candidates/linux-x86_64/lxp.so",
                        destination_path = ".luai/native/lxp.so",
                        sha256 = hash("3"),
                        qualification = "pending",
                    },
                    {
                        role = "curl",
                        source_path = "build/candidates/linux-x86_64/curl",
                        destination_path = ".luai/components/curl",
                        sha256 = hash("4"),
                        qualification = "pending",
                    },
                    {
                        role = "ca_bundle",
                        source_path = "build/sources/cacert-2026-08-13.pem",
                        destination_path = ".luai/components/cacert.pem",
                        sha256 = lock.components["ca-bundle"].sha256,
                        qualification = "pending",
                    },
                })
                A.equal(
                    plan.luainstaller.resource_overlay.status,
                    "required-before-onefile-build-and-target-proof"
                )
                A.falsy(plan.luainstaller.resource_overlay.tree_copy)
                A.deep_equal(
                    planner.policy.builder_patches,
                    lock.components.luainstaller.downstream_patches
                )
            end,
        },
        {
            name = "package planning snapshots inputs and sorts documentation",
            run = function()
                local candidate = inputs("win32-x86")
                candidate.package_files.documents[1], candidate.package_files.documents[3]
                    = candidate.package_files.documents[3], candidate.package_files.documents[1]
                local plan = assert(planner.plan("win32-x86", candidate))
                candidate.artifacts.curl.source_path = "bin/curl.exe"
                candidate.package_files.documents[1].destination_path = "docs/changed.txt"
                A.equal(plan.inner_payload[3].source_path, "build/candidates/win32-x86/curl.exe")
                A.equal(plan.package_files[5].destination_path, "docs/SBOM.spdx.json")
                A.equal(plan.package_files[6].destination_path, "docs/THIRD_PARTY_NOTICES.txt")
                A.equal(plan.package_files[7].destination_path, "docs/USAGE.txt")
            end,
        },
        {
            name = "unknown extra missing and cross-target artifacts fail closed",
            run = function()
                local no_target, no_target_error = planner.plan("macos-arm64", inputs("win32-x86"))
                A.falsy(no_target)
                A.equal(no_target_error.code, "UnknownTarget")

                local extra = inputs("win32-x86")
                extra.artifacts.sqlite3 = clone(extra.artifacts.curl)
                local extra_plan, extra_error = planner.plan("win32-x86", extra)
                A.falsy(extra_plan)
                A.equal(extra_error.code, "UnexpectedPackageComponent")

                local missing = inputs("win32-x86")
                missing.artifacts.lxp = nil
                local missing_plan, missing_error = planner.plan("win32-x86", missing)
                A.falsy(missing_plan)
                A.equal(missing_error.code, "MissingPackageComponent")

                local crossed = inputs("win32-x86")
                crossed.artifacts.curl.target_id = "win64-x86_64"
                local crossed_plan, crossed_error = planner.plan("win32-x86", crossed)
                A.falsy(crossed_plan)
                A.equal(crossed_error.code, "InvalidPackageComponent")
                A.contains(crossed_error.message, "does not match target")
            end,
        },
        {
            name = "historical bin globs and compressed artifacts are never admitted",
            run = function()
                for _, source_path in ipairs({
                    "bin/curl.exe",
                    "./bin/curl.exe",
                    "/checkout/yaca/bin/curl.exe",
                    "build/candidates/win32-x86/*.exe",
                }) do
                    local candidate = inputs("win32-x86")
                    candidate.artifacts.curl.source_path = source_path
                    local plan, plan_error = planner.plan("win32-x86", candidate)
                    A.falsy(plan)
                    A.equal(plan_error.code, "InvalidPackageComponent")
                end
                local compressed = inputs("win32-x86")
                compressed.artifacts.curl.upx = true
                local plan, plan_error = planner.plan("win32-x86", compressed)
                A.falsy(plan)
                A.equal(plan_error.code, "InvalidPackageComponent")
            end,
        },
        {
            name = "transport protocol or runtime dependency creep is rejected",
            run = function()
                local protocol = inputs("linux-x86_64")
                protocol.artifacts.curl.protocols[3] = "ftp"
                local protocol_plan, protocol_error = planner.plan("linux-x86_64", protocol)
                A.falsy(protocol_plan)
                A.equal(protocol_error.code, "InvalidPackageComponent")

                local dependency = inputs("linux-x86_64")
                dependency.artifacts.curl.non_system_runtime_dependencies[1] = "libssl.so"
                local dependency_plan, dependency_error = planner.plan(
                    "linux-x86_64",
                    dependency
                )
                A.falsy(dependency_plan)
                A.equal(dependency_error.code, "InvalidPackageComponent")
            end,
        },
        {
            name = "documentation cannot conceal runtime files or duplicate destinations",
            run = function()
                local hidden = inputs("win64-x86_64")
                hidden.package_files.documents[1].destination_path = "docs/curl.exe"
                local hidden_plan, hidden_error = planner.plan("win64-x86_64", hidden)
                A.falsy(hidden_plan)
                A.equal(hidden_error.code, "InvalidPackageLayout")

                local duplicate = inputs("win64-x86_64")
                duplicate.package_files.documents[2].destination_path = "docs/USAGE.txt"
                local duplicate_plan, duplicate_error = planner.plan(
                    "win64-x86_64",
                    duplicate
                )
                A.falsy(duplicate_plan)
                A.equal(duplicate_error.code, "InvalidPackageLayout")
            end,
        },
        {
            name = "manifest and lock mutation cannot alter an admitted planner",
            run = function()
                manifest.packaging.historical_bin_copy = true
                lock.components.curl.version = "0"
                local plan = assert(planner.plan("linux-x86_64", inputs("linux-x86_64")))
                A.falsy(plan.historical_bin_inputs)
                A.equal(plan.inner_payload[3].role, "curl")
                A.equal(plan.luainstaller.version, "1.3.0")
            end,
        },
    },
}
