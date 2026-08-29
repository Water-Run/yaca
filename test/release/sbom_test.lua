--[[
File: sbom_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies dependency provenance, licenses, and deterministic SPDX data.
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

local function hash(byte)
    return string.rep(byte, 64)
end

local function pending_artifact(path, target_id, object_format, version, digest)
    return {
        source_path = path,
        sha256 = digest,
        target_id = target_id,
        object_format = object_format,
        version = version,
        qualification = "pending",
        compression = "none",
        non_system_runtime_dependencies = {},
    }
end

local function pending_file(path, destination, digest)
    return {
        source_path = path,
        destination_path = destination,
        sha256 = digest,
        qualification = "pending",
    }
end

local function make_plan()
    local planner = assert(module.new(manifest, lock))
    local launcher = pending_artifact(
        "build/candidates/linux-x86_64/yaca",
        "linux-x86_64",
        "ELF64-x86-64",
        "0.1.0",
        hash("1")
    )
    launcher.lua_abi = "5.5"
    launcher.builder_version = "1.3.0"
    launcher.builder_commit = "97192d100077b31b61dc8f94427e14df1c68a9eb"
    launcher.mode = "onefile"
    launcher.upx = false
    local native = pending_artifact(
        "build/candidates/linux-x86_64/yaca_native.so",
        "linux-x86_64",
        "ELF64-x86-64",
        "0.1.0",
        hash("2")
    )
    native.lua_abi = "5.5"
    local lxp = pending_artifact(
        "build/candidates/linux-x86_64/lxp.so",
        "linux-x86_64",
        "ELF64-x86-64",
        "1.5.2",
        hash("3")
    )
    lxp.lua_abi = "5.5"
    local curl = pending_artifact(
        "build/candidates/linux-x86_64/curl",
        "linux-x86_64",
        "ELF64-x86-64",
        "8.21.0",
        hash("4")
    )
    curl.tls_backend = "mbedtls-3.6.7"
    curl.protocols = { "http", "https" }
    curl.ca_bundle_sha256 = lock.components["ca-bundle"].sha256
    curl.upx = false
    local inputs = {
        source_revision = "0123456789abcdef0123456789abcdef01234567",
        artifacts = {
            launcher = launcher,
            yaca_native = native,
            lxp = lxp,
            curl = curl,
            ca_bundle = pending_artifact(
                "build/sources/cacert-2026-08-13.pem",
                "all",
                "PEM",
                "2026-08-13",
                lock.components["ca-bundle"].sha256
            ),
        },
        package_files = {
            installer = pending_file(
                "build/package-inputs/linux-x86_64/Install.sh",
                "Install.sh",
                hash("5")
            ),
            readme = pending_file(
                "build/package-inputs/linux-x86_64/README.txt",
                "README.txt",
                hash("6")
            ),
            license = pending_file(
                "build/package-inputs/linux-x86_64/LICENSE",
                "LICENSE",
                hash("7")
            ),
            documents = {
                pending_file(
                    "build/package-inputs/linux-x86_64/USAGE.txt",
                    "docs/USAGE.txt",
                    hash("8")
                ),
                pending_file(
                    "build/package-inputs/linux-x86_64/THIRD_PARTY_NOTICES.txt",
                    "docs/THIRD_PARTY_NOTICES.txt",
                    hash("9")
                ),
            },
        },
    }
    return planner, assert(planner.plan("linux-x86_64", inputs))
end

local function packages_by_id(sbom)
    local result = {}
    for _, package in ipairs(sbom.packages) do result[package.SPDXID] = package end
    return result
end

return {
    name = "release/sbom",
    cases = {
        {
            name = "all shipped source components have exact provenance and licenses",
            run = function()
                A.deep_equal(lock.component_order, {
                    "yaca", "luainstaller", "lua", "luaexpat", "expat",
                    "curl", "mbedtls", "ca-bundle",
                })
                local revisions = 0
                for _, name in ipairs(lock.component_order) do
                    local component = lock.components[name]
                    A.truthy(component.shipped)
                    A.equal(component.qualification, "pending-all-targets")
                    A.type(component.license, "string")
                    A.type(component.source_url, "string")
                    if component.source_type == "archive" or component.source_type == "file" then
                        A.matches(component.sha256, "^[0-9a-f]+$")
                        A.equal(#component.sha256, 64)
                    else
                        revisions = revisions + 1
                    end
                end
                A.equal(revisions, 2)
                A.equal(
                    lock.components.luainstaller.revision,
                    "97192d100077b31b61dc8f94427e14df1c68a9eb"
                )
                A.deep_equal(
                    manifest.dependencies.luainstaller.downstream_patches,
                    lock.components.luainstaller.downstream_patches
                )
                A.equal(
                    lock.components.luainstaller.downstream_patches[1].sha256,
                    "974cf25b51ab644c8af60a7f2524a5670b1fea38e35ad733267ac4775c5d9dff"
                )
                A.equal(lock.components.curl.version, "8.21.0")
                A.equal(
                    lock.components.curl.sha256,
                    "aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6"
                )
                A.equal(lock.components.mbedtls.version, "3.6.7")
                A.equal(
                    lock.components["ca-bundle"].sha256,
                    "f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9"
                )
                A.equal(lock.components["ca-bundle"].license, "MPL-2.0")
            end,
        },
        {
            name = "curl closure is HTTP only static and honestly target-pending",
            run = function()
                A.deep_equal(lock.curl_profile.protocols, { "http", "https" })
                A.equal(lock.curl_profile.tls_component, "mbedtls")
                A.equal(lock.curl_profile.ca_component, "ca-bundle")
                A.equal(lock.curl_profile.linkage, "static-tls-closure")
                A.equal(#lock.curl_profile.allowed_non_system_runtime_dependencies, 0)
                A.falsy(lock.curl_profile.automatic_retry)
                A.falsy(lock.curl_profile.automatic_redirect)
                A.falsy(lock.curl_profile.ambient_config)
                A.falsy(lock.curl_profile.ambient_ca)
                A.falsy(lock.curl_profile.upx)
                A.equal(lock.curl_profile.target_compatibility.qualification, "pending")
                A.contains(
                    lock.curl_profile.target_compatibility.upstream_windows_minimum,
                    "Vista"
                )
                A.contains(lock.curl_profile.target_compatibility.win32_xp, "proof-required")
            end,
        },
        {
            name = "SPDX document is deterministic ordered and remains unqualified",
            run = function()
                local planner, plan = make_plan()
                local first = assert(planner.sbom(plan))
                local second = assert(planner.sbom(plan))
                A.deep_equal(first, second)
                A.equal(first.spdxVersion, "SPDX-2.3")
                A.equal(first.dataLicense, "CC0-1.0")
                A.equal(first.SPDXID, "SPDXRef-DOCUMENT")
                A.equal(first.creationInfo.created, "2026-08-30T00:00:00Z")
                A.equal(#first.packages, #lock.component_order)
                for index, name in ipairs(lock.component_order) do
                    A.equal(first.packages[index].SPDXID, lock.components[name].spdx_id)
                    A.falsy(first.packages[index].filesAnalyzed)
                end
                A.contains(first.annotations[1].comment, "candidate-unqualified")
                A.contains(first.annotations[1].comment, "linux-x86_64")
            end,
        },
        {
            name = "SPDX packages preserve hashes revisions and declared license choices",
            run = function()
                local planner, plan = make_plan()
                local sbom = assert(planner.sbom(plan))
                local packages = packages_by_id(sbom)
                A.equal(
                    packages["SPDXRef-Package-curl"].checksums[1].checksumValue,
                    lock.components.curl.sha256
                )
                A.equal(
                    packages["SPDXRef-Package-mbedtls"].licenseDeclared,
                    "Apache-2.0"
                )
                A.equal(packages["SPDXRef-Package-ca-bundle"].licenseDeclared, "MPL-2.0")
                A.contains(
                    packages["SPDXRef-Package-yaca"].externalRefs[1].referenceLocator,
                    plan.source_revision
                )
                A.contains(
                    packages["SPDXRef-Package-luainstaller"].externalRefs[1]
                        .referenceLocator,
                    lock.components.luainstaller.revision
                )
                A.contains(
                    packages["SPDXRef-Package-luainstaller"].comment,
                    lock.components.luainstaller.downstream_patches[1].sha256
                )
            end,
        },
        {
            name = "SPDX relationships describe the complete static dependency closure",
            run = function()
                local planner, plan = make_plan()
                local relationships = assert(planner.sbom(plan)).relationships
                A.deep_equal(relationships, {
                    {
                        spdxElementId = "SPDXRef-DOCUMENT",
                        relationshipType = "DESCRIBES",
                        relatedSpdxElement = "SPDXRef-Package-yaca",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-yaca",
                        relationshipType = "GENERATED_FROM",
                        relatedSpdxElement = "SPDXRef-Package-luainstaller",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-yaca",
                        relationshipType = "DEPENDS_ON",
                        relatedSpdxElement = "SPDXRef-Package-lua",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-yaca",
                        relationshipType = "DEPENDS_ON",
                        relatedSpdxElement = "SPDXRef-Package-luaexpat",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-luaexpat",
                        relationshipType = "STATIC_LINK",
                        relatedSpdxElement = "SPDXRef-Package-expat",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-yaca",
                        relationshipType = "DEPENDS_ON",
                        relatedSpdxElement = "SPDXRef-Package-curl",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-curl",
                        relationshipType = "STATIC_LINK",
                        relatedSpdxElement = "SPDXRef-Package-mbedtls",
                    },
                    {
                        spdxElementId = "SPDXRef-Package-curl",
                        relationshipType = "DEPENDS_ON",
                        relatedSpdxElement = "SPDXRef-Package-ca-bundle",
                    },
                })
            end,
        },
        {
            name = "component license manifest contains every notice obligation",
            run = function()
                local planner, plan = make_plan()
                local licenses = assert(planner.license_manifest(plan))
                A.equal(licenses.status, "candidate-unqualified")
                A.falsy(licenses.release_authorized)
                A.truthy(licenses.notices_in_archive)
                A.truthy(licenses.corresponding_source_reference_required)
                A.deep_equal(licenses.required_license_ids, {
                    "GPL-3.0-only", "LGPL-3.0-or-later", "MIT", "curl",
                    "Apache-2.0", "MPL-2.0",
                })
                A.equal(#licenses.components, #lock.component_order)
                for index, name in ipairs(lock.component_order) do
                    local component = licenses.components[index]
                    A.equal(component.id, name)
                    A.equal(component.declared_license, lock.components[name].license)
                    if name == "yaca" then
                        A.equal(component.source_revision, plan.source_revision)
                    elseif name == "luainstaller" then
                        A.deep_equal(
                            component.downstream_patches,
                            lock.components.luainstaller.downstream_patches
                        )
                    end
                end
            end,
        },
        {
            name = "caller mutation cannot rewrite admitted evidence",
            run = function()
                local planner, plan = make_plan()
                local expected = assert(planner.sbom(plan))
                plan.source_revision = string.rep("f", 40)
                plan.target_id = "win32-x86"
                plan.release_authorized = true
                local after_plan_mutation = assert(planner.sbom(plan))
                A.deep_equal(after_plan_mutation, expected)
                expected.packages[1].name = "tampered"
                local after_output_mutation = assert(planner.sbom(plan))
                A.equal(after_output_mutation.packages[1].name, "yaca")
                A.contains(after_output_mutation.annotations[1].comment, "linux-x86_64")
            end,
        },
        {
            name = "foreign plans and release-authorizing policy mutations fail closed",
            run = function()
                local planner = assert(module.new(manifest, lock))
                local sbom, sbom_error = planner.sbom({})
                A.falsy(sbom)
                A.equal(sbom_error.code, "UnknownPackagePlan")

                local altered_lock = clone(lock)
                altered_lock.release_authorized = true
                local altered, altered_error = module.new(manifest, altered_lock)
                A.falsy(altered)
                A.equal(altered_error.code, "InvalidDependencyLock")

                local altered_manifest = clone(manifest)
                altered_manifest.release_authorized = true
                local admitted, admitted_error = module.new(altered_manifest, lock)
                A.falsy(admitted)
                A.equal(admitted_error.code, "InvalidReleaseManifest")

                local altered_patch_lock = clone(lock)
                altered_patch_lock.components.luainstaller.downstream_patches[1].sha256
                    = string.rep("0", 64)
                local patch_planner, patch_error = module.new(manifest, altered_patch_lock)
                A.falsy(patch_planner)
                A.equal(patch_error.code, "InvalidDependencyLock")

                local altered_patch_manifest = clone(manifest)
                altered_patch_manifest.dependencies.luainstaller.downstream_patches[1].purpose
                    = "different-purpose"
                local manifest_planner, manifest_error = module.new(
                    altered_patch_manifest,
                    lock
                )
                A.falsy(manifest_planner)
                A.equal(manifest_error.code, "InvalidReleaseManifest")
            end,
        },
        {
            name = "historical utility surface is absent from lock SBOM and allowlist",
            run = function()
                local forbidden = {
                    sqlite3 = true, jq = true, ["7za"] = true, busybox = true,
                    ["web-server"] = true, ["plugin-loader"] = true,
                }
                for _, name in ipairs(lock.component_order) do A.falsy(forbidden[name]) end
                for _, name in ipairs(manifest.packaging.shipped_component_allowlist) do
                    A.falsy(forbidden[name])
                end
                A.falsy(lock.historical_bin_policy.copy_tree)
                A.falsy(lock.historical_bin_policy.accept_individual_file)
            end,
        },
    },
}
