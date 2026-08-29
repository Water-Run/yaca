--[[
File: luainstaller.lua
Date: 2026-08-30
Author: WaterRun
Description: Plans deterministic minimal packages without authorizing release.
]]

local M = {}

local TARGET_ORDER = { "win32-x86", "win64-x86_64", "linux-x86_64" }
local ARTIFACT_ORDER = { "launcher", "yaca_native", "lxp", "curl", "ca_bundle" }
local PAYLOAD_ORDER = { "yaca_native", "lxp", "curl", "ca_bundle" }

local INPUT_FIELDS = {
    source_revision = true,
    artifacts = true,
    package_files = true,
}

local ARTIFACT_FIELDS = {
    source_path = true,
    sha256 = true,
    target_id = true,
    object_format = true,
    lua_abi = true,
    version = true,
    qualification = true,
    compression = true,
    non_system_runtime_dependencies = true,
    builder_version = true,
    builder_commit = true,
    mode = true,
    tls_backend = true,
    protocols = true,
    ca_bundle_sha256 = true,
    upx = true,
}

local PACKAGE_FILE_FIELDS = {
    source_path = true,
    sha256 = true,
    destination_path = true,
    qualification = true,
}

local PURPOSES = {
    application = "APPLICATION",
    ["build-tool-and-generated-runtime"] = "SOURCE",
    runtime = "LIBRARY",
    library = "LIBRARY",
    data = "FILE",
}

local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
    return nil, result
end

local function copy(value, visiting)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    local result = {}
    for key, item in pairs(value) do
        local copied = copy(item, visiting)
        if copied == nil and type(item) == "table" then
            visiting[value] = nil
            return nil
        end
        result[key] = copied
    end
    visiting[value] = nil
    return result
end

local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then return nil end
    end
    return count
end

local function known_fields(value, allowed, label)
    if type(value) ~= "table" then
        return nil, label .. " must be a table"
    end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, label .. " contains an unknown field"
        end
    end
    return true
end

local function is_sha256(value)
    return type(value) == "string"
        and #value == 64
        and value:match("^[0-9a-f]+$") ~= nil
end

local function is_revision(value)
    return type(value) == "string"
        and #value == 40
        and value:match("^[0-9a-f]+$") ~= nil
end

local function normalize_path(value)
    if type(value) ~= "string" then return nil end
    return value:gsub("\\", "/")
end

local function safe_path(value, source)
    value = normalize_path(value)
    if not value or value == "" or value:find("\0", 1, true)
        or value:find("*", 1, true) or value:find("?", 1, true)
        or value:find("[", 1, true) or value:find("]", 1, true)
        or value:find("{", 1, true) or value:find("}", 1, true)
    then
        return false
    end
    for segment in value:gmatch("[^/]+") do
        if segment == "." or segment == ".." then return false end
        if source and segment:lower() == "bin" then return false end
    end
    return true
end

local function same_array(left, right)
    local left_count = dense_count(left)
    local right_count = dense_count(right)
    if not left_count or not right_count or left_count ~= right_count then return false end
    for index = 1, left_count do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function is_empty_array(values)
    return dense_count(values) == 0
end

local function unique_array(values, label)
    local count = dense_count(values)
    if not count then return nil, label .. " must be a dense array" end
    local seen = {}
    for index = 1, count do
        local value = values[index]
        if type(value) ~= "string" or value == "" or seen[value] then
            return nil, label .. " contains an invalid or repeated value"
        end
        seen[value] = true
    end
    return seen
end

local function validate_lock(lock)
    if type(lock) ~= "table" or lock.schema_version ~= "yaca-dependency-lock-v1" then
        return nil, "unexpected dependency lock schema"
    end
    if lock.release_authorized ~= false or lock.target_artifacts_qualified ~= false then
        return nil, "dependency lock must not authorize unqualified artifacts"
    end
    if lock.hash_algorithm ~= "sha256" then return nil, "dependency lock must use sha256" end
    local component_set, component_error = unique_array(
        lock.component_order,
        "dependency component order"
    )
    if not component_set then return nil, component_error end
    if type(lock.components) ~= "table" then return nil, "dependency components are missing" end
    for name in pairs(lock.components) do
        if not component_set[name] then return nil, "unordered dependency component " .. tostring(name) end
    end
    for _, name in ipairs(lock.component_order) do
        local component = lock.components[name]
        if type(component) ~= "table" or component.shipped ~= true
            or type(component.version) ~= "string" or component.version == ""
            or type(component.spdx_id) ~= "string" or component.spdx_id == ""
            or type(component.license) ~= "string" or component.license == ""
            or type(component.source_url) ~= "string" or component.source_url == ""
            or component.qualification ~= "pending-all-targets"
        then
            return nil, "incomplete dependency component " .. tostring(name)
        end
        if component.source_type == "archive" or component.source_type == "file" then
            if not is_sha256(component.sha256) then
                return nil, "dependency source has no sha256: " .. tostring(name)
            end
        elseif component.source_type == "git" then
            if name == "luainstaller" and not is_revision(component.revision) then
                return nil, "luainstaller revision is not fully pinned"
            end
            if name == "yaca" and component.revision_policy ~= "exact-build-commit" then
                return nil, "yaca source revision policy is not exact"
            end
        else
            return nil, "unsupported dependency source type: " .. tostring(name)
        end
    end
    if type(lock.historical_bin_policy) ~= "table"
        or lock.historical_bin_policy.copy_tree ~= false
        or lock.historical_bin_policy.accept_individual_file ~= false
    then
        return nil, "historical bin policy must reject every historical input"
    end
    if type(lock.curl_profile) ~= "table"
        or not same_array(lock.curl_profile.protocols, { "http", "https" })
        or lock.curl_profile.tls_component ~= "mbedtls"
        or lock.curl_profile.ca_component ~= "ca-bundle"
        or lock.curl_profile.upx ~= false
        or not is_empty_array(lock.curl_profile.allowed_non_system_runtime_dependencies)
        or type(lock.curl_profile.target_compatibility) ~= "table"
        or lock.curl_profile.target_compatibility.qualification ~= "pending"
    then
        return nil, "curl profile is not the minimal unqualified static profile"
    end
    for _, target_id in ipairs(TARGET_ORDER) do
        local target = lock.target_policy and lock.target_policy[target_id]
        if type(target) ~= "table" or target.id ~= target_id
            or target.qualification ~= "pending"
        then
            return nil, "dependency lock omits pending target " .. target_id
        end
    end
    return true
end

local function validate_manifest(manifest, lock)
    if type(manifest) ~= "table"
        or manifest.schema_version ~= "yaca-release-manifest-v0.1.0"
        or manifest.product_version ~= "0.1.0"
        or manifest.release_state ~= "unqualified"
        or manifest.release_authorized ~= false
        or manifest.target_qualification_complete ~= false
    then
        return nil, "release manifest is not an unqualified v0.1.0 manifest"
    end
    if manifest.dependency_lock ~= "release/dependencies.lock" then
        return nil, "release manifest does not bind the dependency lock"
    end
    if type(manifest.packaging) ~= "table"
        or manifest.packaging.builder ~= "luainstaller-1.3.0"
        or manifest.packaging.builder_mode ~= "onefile-from-qualified-onedir"
        or manifest.packaging.package_assembly ~= "explicit-files-only"
        or manifest.packaging.historical_bin_copy ~= false
        or manifest.packaging.compression_of_native_inputs ~= false
    then
        return nil, "release manifest has an unsafe package policy"
    end
    if manifest.dependencies.luainstaller.full_commit
        ~= lock.components.luainstaller.revision
        or manifest.dependencies.curl.sha256 ~= lock.components.curl.sha256
        or manifest.dependencies.mbedtls.sha256 ~= lock.components.mbedtls.sha256
        or manifest.dependencies.ca_bundle.sha256 ~= lock.components["ca-bundle"].sha256
    then
        return nil, "release manifest and dependency lock disagree"
    end
    local target_count = dense_count(manifest.targets)
    if target_count ~= #TARGET_ORDER then return nil, "release manifest target count changed" end
    for index, target_id in ipairs(TARGET_ORDER) do
        local target = manifest.targets[index]
        local locked = lock.target_policy[target_id]
        if target.id ~= target_id or target.os ~= locked.os or target.arch ~= locked.arch
            or target.minimum ~= locked.minimum or target.object_format ~= locked.object_format
            or target.qualification ~= "pending"
        then
            return nil, "release target disagrees with dependency lock: " .. target_id
        end
    end
    return true
end

local function validate_artifact(role, artifact, target, lock, product_version)
    local fields_ok, fields_error = known_fields(artifact, ARTIFACT_FIELDS, role)
    if not fields_ok then return nil, fields_error end
    if not safe_path(artifact.source_path, true) then
        return nil, role .. " source path is unsafe or references historical bin"
    end
    if not is_sha256(artifact.sha256) then return nil, role .. " has no sha256" end
    if artifact.qualification ~= "pending" or artifact.compression ~= "none"
        or not is_empty_array(artifact.non_system_runtime_dependencies)
    then
        return nil, role .. " is not an uncompressed dependency-closed pending artifact"
    end

    local expected_target = role == "ca_bundle" and "all" or target.id
    local expected_format = role == "ca_bundle" and "PEM" or target.object_format
    if artifact.target_id ~= expected_target or artifact.object_format ~= expected_format then
        return nil, role .. " does not match target " .. target.id
    end

    if role == "launcher" then
        if artifact.version ~= product_version or artifact.lua_abi ~= "5.5"
            or artifact.builder_version ~= lock.components.luainstaller.version
            or artifact.builder_commit ~= lock.components.luainstaller.revision
            or artifact.mode ~= "onefile" or artifact.upx ~= false
        then
            return nil, "launcher does not match the pinned onefile builder"
        end
    elseif role == "yaca_native" then
        if artifact.version ~= product_version or artifact.lua_abi ~= "5.5" then
            return nil, "yaca_native does not match the product Lua ABI"
        end
    elseif role == "lxp" then
        if artifact.version ~= lock.components.luaexpat.version or artifact.lua_abi ~= "5.5" then
            return nil, "lxp does not match the locked LuaExpat Lua ABI"
        end
    elseif role == "curl" then
        if artifact.version ~= lock.components.curl.version
            or artifact.tls_backend ~= "mbedtls-" .. lock.components.mbedtls.version
            or not same_array(artifact.protocols, lock.curl_profile.protocols)
            or artifact.ca_bundle_sha256 ~= lock.components["ca-bundle"].sha256
            or artifact.upx ~= false
        then
            return nil, "curl does not match the locked minimal transport profile"
        end
    elseif role == "ca_bundle" then
        if artifact.version ~= lock.components["ca-bundle"].version
            or artifact.sha256 ~= lock.components["ca-bundle"].sha256
        then
            return nil, "CA bundle bytes do not match the source lock"
        end
    end
    return true
end

local function validate_package_file(file, destination, label)
    local fields_ok, fields_error = known_fields(file, PACKAGE_FILE_FIELDS, label)
    if not fields_ok then return nil, fields_error end
    if not safe_path(file.source_path, true) then
        return nil, label .. " source path is unsafe or references historical bin"
    end
    if not is_sha256(file.sha256) or file.qualification ~= "pending" then
        return nil, label .. " must be a hashed pending file"
    end
    if destination and file.destination_path ~= destination then
        return nil, label .. " has an unexpected package destination"
    end
    if not safe_path(file.destination_path, false)
        or file.destination_path:sub(1, 1) == "/"
        or file.destination_path:match("^[A-Za-z]:/")
    then
        return nil, label .. " destination is not a safe relative path"
    end
    return true
end

local function validate_package_files(files, target)
    local allowed = { installer = true, readme = true, license = true, documents = true }
    local fields_ok, fields_error = known_fields(files, allowed, "package_files")
    if not fields_ok then return nil, fields_error end
    for name in pairs(allowed) do
        if files[name] == nil then return nil, "package_files omits " .. name end
    end
    local expected = {
        installer = target.installer,
        readme = "README.txt",
        license = "LICENSE",
    }
    local destinations = { [target.executable] = true }
    for _, name in ipairs({ "installer", "readme", "license" }) do
        local valid, validation_error = validate_package_file(files[name], expected[name], name)
        if not valid then return nil, validation_error end
        if destinations[files[name].destination_path] then
            return nil, "package destination repeats " .. files[name].destination_path
        end
        destinations[files[name].destination_path] = true
    end
    local document_count = dense_count(files.documents)
    if not document_count or document_count == 0 then
        return nil, "package documents must be a non-empty dense array"
    end
    for index, document in ipairs(files.documents) do
        local valid, validation_error = validate_package_file(
            document,
            nil,
            "documents[" .. index .. "]"
        )
        if not valid then return nil, validation_error end
        local destination = document.destination_path
        if destination:sub(1, 5) ~= "docs/" or destination == "docs/"
            or destination:lower():match("%.exe$")
            or destination:lower():match("%.dll$")
            or destination:lower():match("%.so$")
            or destination:lower():match("%.pem$")
        then
            return nil, "documents may not hide runtime components"
        end
        if destinations[destination] then return nil, "package destination repeats " .. destination end
        destinations[destination] = true
    end
    return true
end

local function destination_for_payload(role, target, manifest)
    if role == "yaca_native" then
        return ".luai/native/" .. manifest.native_module_filenames[target.id].yaca_native
    end
    if role == "lxp" then
        return ".luai/native/" .. manifest.native_module_filenames[target.id].lxp
    end
    if role == "curl" then return ".luai/components/" .. target.curl_executable end
    return ".luai/components/cacert.pem"
end

local function spdx_package(name, component, source_revision)
    local package = {
        name = component.name,
        SPDXID = component.spdx_id,
        versionInfo = component.version,
        downloadLocation = component.source_url,
        filesAnalyzed = false,
        licenseConcluded = component.license,
        licenseDeclared = component.license,
        copyrightText = "NOASSERTION",
        primaryPackagePurpose = PURPOSES[component.purpose] or "OTHER",
        comment = component.delivery .. "; qualification pending for all targets",
    }
    if component.sha256 then
        package.checksums = {
            { algorithm = "SHA256", checksumValue = component.sha256 },
        }
    end
    local revision = name == "yaca" and source_revision or component.revision
    if revision then
        package.externalRefs = {
            {
                referenceCategory = "OTHER",
                referenceType = "vcs",
                referenceLocator = component.source_url .. "@" .. revision,
            },
        }
    end
    return package
end

---Creates a release planner from snapshotted manifest and dependency lock data.
-- The planner performs no filesystem or network operation.  Every result stays
-- explicitly unqualified until C32 supplies independent target evidence.
-- @param manifest table Loaded release/manifest.lua value.
-- @param lock table Loaded release/dependencies.lock value.
-- @return table|nil planner Candidate package planner.
-- @return table|nil err Structured validation failure.
function M.new(manifest, lock)
    local lock_ok, lock_error = validate_lock(lock)
    if not lock_ok then return failure("InvalidDependencyLock", lock_error) end
    local manifest_ok, manifest_error = validate_manifest(manifest, lock)
    if not manifest_ok then return failure("InvalidReleaseManifest", manifest_error) end
    local admitted_manifest = copy(manifest)
    local admitted_lock = copy(lock)
    if not admitted_manifest or not admitted_lock then
        return failure("InvalidReleasePolicy", "release policy contains a cycle")
    end

    local targets = {}
    for _, target in ipairs(admitted_manifest.targets) do targets[target.id] = target end
    local owned_plans = setmetatable({}, { __mode = "k" })
    local service = {}

    ---Plans one exact candidate archive from already-built, hashed inputs.
    -- @param target_id string One of the three release target IDs.
    -- @param inputs table Exact source revision, runtime artifacts, and outer files.
    -- @return table|nil plan Plain deterministic assembly plan.
    -- @return table|nil err Structured validation failure.
    function service.plan(target_id, inputs)
        local target = targets[target_id]
        if not target then return failure("UnknownTarget", "unknown release target") end
        local fields_ok, fields_error = known_fields(inputs, INPUT_FIELDS, "package inputs")
        if not fields_ok then return failure("InvalidPackageInputs", fields_error) end
        if not is_revision(inputs.source_revision) then
            return failure("InvalidSourceRevision", "package source revision must be a full git commit")
        end
        if type(inputs.artifacts) ~= "table" then
            return failure("InvalidPackageInputs", "package artifacts are required")
        end
        local expected_artifacts = {}
        for _, role in ipairs(ARTIFACT_ORDER) do expected_artifacts[role] = true end
        for role in pairs(inputs.artifacts) do
            if not expected_artifacts[role] then
                return failure("UnexpectedPackageComponent", "artifact is not allowlisted: " .. tostring(role))
            end
        end
        local source_paths = {}
        for _, role in ipairs(ARTIFACT_ORDER) do
            local artifact = inputs.artifacts[role]
            if artifact == nil then
                return failure("MissingPackageComponent", "artifact is required: " .. role)
            end
            local valid, validation_error = validate_artifact(
                role,
                artifact,
                target,
                admitted_lock,
                admitted_manifest.product_version
            )
            if not valid then return failure("InvalidPackageComponent", validation_error) end
            local source_path = normalize_path(artifact.source_path)
            if source_paths[source_path] then
                return failure("DuplicatePackageSource", "artifact source is repeated")
            end
            source_paths[source_path] = true
        end
        local package_files_ok, package_files_error = validate_package_files(
            inputs.package_files,
            target
        )
        if not package_files_ok then
            return failure("InvalidPackageLayout", package_files_error)
        end

        local inner_payload = {}
        for _, role in ipairs(PAYLOAD_ORDER) do
            local artifact = inputs.artifacts[role]
            inner_payload[#inner_payload + 1] = {
                role = role,
                source_path = normalize_path(artifact.source_path),
                destination_path = destination_for_payload(
                    role,
                    admitted_lock.target_policy[target_id],
                    admitted_manifest
                ),
                sha256 = artifact.sha256,
                qualification = "pending",
            }
        end

        local package_files = {
            {
                role = "executable",
                source_path = normalize_path(inputs.artifacts.launcher.source_path),
                destination_path = target.executable,
                sha256 = inputs.artifacts.launcher.sha256,
            },
        }
        for _, name in ipairs({ "installer", "readme", "license" }) do
            local file = inputs.package_files[name]
            package_files[#package_files + 1] = {
                role = name,
                source_path = normalize_path(file.source_path),
                destination_path = file.destination_path,
                sha256 = file.sha256,
            }
        end
        local documents = copy(inputs.package_files.documents)
        table.sort(documents, function(left, right)
            return left.destination_path < right.destination_path
        end)
        for _, file in ipairs(documents) do
            package_files[#package_files + 1] = {
                role = "documentation",
                source_path = normalize_path(file.source_path),
                destination_path = file.destination_path,
                sha256 = file.sha256,
            }
        end

        local root_entries = copy(
            admitted_manifest.packaging.required_root_entries[target.os]
        )
        local plan = {
            schema_version = "yaca-package-plan-v1",
            policy_id = "yaca-minimal-package-v0.1.0",
            product_version = admitted_manifest.product_version,
            source_revision = inputs.source_revision,
            target_id = target_id,
            target_os = target.os,
            target_arch = target.arch,
            target_minimum = target.minimum,
            object_format = target.object_format,
            archive = target.archive,
            status = "candidate-unqualified",
            release_authorized = false,
            target_qualification_complete = false,
            root_entries = root_entries,
            package_files = package_files,
            outer_runtime_components = {},
            inner_payload = inner_payload,
            luainstaller = {
                version = admitted_lock.components.luainstaller.version,
                tag = admitted_lock.components.luainstaller.tag,
                commit = admitted_lock.components.luainstaller.revision,
                prerequisite_mode = "onedir",
                final_mode = "onefile",
                entry = "src/main.lua",
                discovery_mode = "manual",
                lua_abi = "5.5",
                lua_modules = copy(admitted_manifest.lua_modules),
                native_modules = copy(admitted_manifest.native_modules),
                resource_overlay = {
                    status = "required-before-onefile-build-and-target-proof",
                    explicit_files_only = true,
                    tree_copy = false,
                    files = copy(inner_payload),
                },
            },
            runtime_paths = {
                curl = destination_for_payload(
                    "curl",
                    admitted_lock.target_policy[target_id],
                    admitted_manifest
                ),
                ca_bundle = destination_for_payload(
                    "ca_bundle",
                    admitted_lock.target_policy[target_id],
                    admitted_manifest
                ),
            },
            component_allowlist = copy(
                admitted_manifest.packaging.shipped_component_allowlist
            ),
            forbidden_components = copy(
                admitted_manifest.packaging.forbidden_shipped_components
            ),
            historical_bin_inputs = false,
            compressed_native_inputs = false,
            evidence_required = copy(admitted_manifest.packaging.evidence_per_target),
        }
        local canonical = copy(plan)
        if not canonical then return failure("InvalidPackagePlan", "package plan contains a cycle") end
        owned_plans[plan] = canonical
        return plan
    end

    local function admitted_plan(plan)
        local canonical = owned_plans[plan]
        if not canonical then return failure("UnknownPackagePlan", "plan was not created by this planner") end
        return copy(canonical)
    end

    ---Projects a deterministic SPDX 2.3 source-component SBOM for one plan.
    -- @param plan table Plan returned by this planner.
    -- @return table|nil sbom JSON-compatible SPDX document data.
    -- @return table|nil err Structured validation failure.
    function service.sbom(plan)
        local canonical, plan_error = admitted_plan(plan)
        if not canonical then return nil, plan_error end
        local packages = {}
        for _, name in ipairs(admitted_lock.component_order) do
            packages[#packages + 1] = spdx_package(
                name,
                admitted_lock.components[name],
                canonical.source_revision
            )
        end
        local relationships = {
            {
                spdxElementId = "SPDXRef-DOCUMENT",
                relationshipType = "DESCRIBES",
                relatedSpdxElement = admitted_lock.components.yaca.spdx_id,
            },
        }
        for _, relationship in ipairs(admitted_lock.relationships) do
            relationships[#relationships + 1] = {
                spdxElementId = admitted_lock.components[relationship.from].spdx_id,
                relationshipType = relationship.kind,
                relatedSpdxElement = admitted_lock.components[relationship.to].spdx_id,
            }
        end
        return {
            spdxVersion = admitted_lock.license_policy.spdx_version,
            dataLicense = admitted_lock.license_policy.spdx_data_license,
            SPDXID = "SPDXRef-DOCUMENT",
            name = canonical.archive .. " source-component SBOM",
            documentNamespace = "https://github.com/Water-Run/yaca/releases/spdx/"
                .. canonical.product_version .. "/" .. canonical.target_id .. "/"
                .. canonical.source_revision,
            creationInfo = {
                created = admitted_lock.lock_date .. "T00:00:00Z",
                creators = { "Tool: yaca-release-planner-0.1.0" },
            },
            documentDescribes = { admitted_lock.components.yaca.spdx_id },
            packages = packages,
            relationships = relationships,
            annotations = {
                {
                    annotationDate = admitted_lock.lock_date .. "T00:00:00Z",
                    annotationType = "OTHER",
                    annotator = "Tool: yaca-release-planner-0.1.0",
                    comment = "candidate-unqualified; independent target evidence is pending for "
                        .. canonical.target_id,
                },
            },
        }
    end

    ---Projects the source, license, and delivery manifest for one candidate.
    -- @param plan table Plan returned by this planner.
    -- @return table|nil manifest Plain deterministic license data.
    -- @return table|nil err Structured validation failure.
    function service.license_manifest(plan)
        local canonical, plan_error = admitted_plan(plan)
        if not canonical then return nil, plan_error end
        local components = {}
        for _, name in ipairs(admitted_lock.component_order) do
            local component = admitted_lock.components[name]
            local entry = {
                id = name,
                name = component.name,
                version = component.version,
                declared_license = component.license,
                delivery = component.delivery,
                source_url = component.source_url,
                shipped = component.shipped,
                qualification = component.qualification,
            }
            if component.sha256 then entry.source_sha256 = component.sha256 end
            if component.revision then entry.source_revision = component.revision end
            if name == "yaca" then entry.source_revision = canonical.source_revision end
            components[#components + 1] = entry
        end
        return {
            schema_version = "yaca-component-license-manifest-v1",
            product = "yaca",
            product_version = canonical.product_version,
            target_id = canonical.target_id,
            archive = canonical.archive,
            source_revision = canonical.source_revision,
            status = "candidate-unqualified",
            release_authorized = false,
            components = components,
            required_license_ids = copy(
                admitted_lock.license_policy.required_license_ids
            ),
            notices_in_archive = admitted_lock.license_policy.notices_in_archive,
            corresponding_source_reference_required = admitted_lock.license_policy
                .corresponding_source_reference_required,
        }
    end

    service.schema_version = "yaca-package-planner-v1"
    service.target_order = copy(TARGET_ORDER)
    service.policy = {
        release_authorized = false,
        target_qualification_complete = false,
        historical_bin_copy = false,
        exact_files_only = true,
        builder_version = admitted_lock.components.luainstaller.version,
        builder_commit = admitted_lock.components.luainstaller.revision,
    }
    return service
end

return M
