--[[
File: legacy_https_patch_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the exact Windows XP HTTPS compatibility patch closure.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local SHA256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()

local function load_value(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    local ok, value = pcall(chunk)
    A.truthy(ok, value)
    return value
end

local function read_bytes(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local bytes = handle:read("a")
    local close_ok, close_error = handle:close()
    A.truthy(close_ok, close_error)
    return bytes
end

local function patch_files(bytes)
    local old_files, new_files = {}, {}
    for line in (bytes .. "\n"):gmatch("([^\n]*)\n") do
        local old_file = line:match("^%-%-%- a/(.+)$")
        local new_file = line:match("^%+%+%+ b/(.+)$")
        if old_file then old_files[#old_files + 1] = old_file end
        if new_file then new_files[#new_files + 1] = new_file end
    end
    return old_files, new_files
end

local function additions(bytes)
    local result = {}
    for line in (bytes .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
            result[#result + 1] = line:sub(2)
        end
    end
    return table.concat(result, "\n")
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

local lock = load_value("release/dependencies.lock")
local manifest = load_value("release/manifest.lua")
local planner_module = load_value("release/luainstaller.lua")
local curl_record = lock.components.curl.downstream_patches[1]
local mbedtls_record = lock.components.mbedtls.downstream_patches[1]
local curl_patch = read_bytes(curl_record.path)
local mbedtls_patch = read_bytes(mbedtls_record.path)
local candidate_build = read_bytes(
    ".tools/qualification/build_win32_xp_https_candidate.sh"
)

return {
    name = "release/legacy-https-patch",
    cases = {
        {
            name = "archive patch bytes source bindings and target scope are exactly pinned",
            run = function()
                A.equal(#lock.components.curl.downstream_patches, 1)
                A.equal(#lock.components.mbedtls.downstream_patches, 1)
                A.equal(curl_record.applies_to_source_sha256, lock.components.curl.sha256)
                A.equal(mbedtls_record.applies_to_source_sha256, lock.components.mbedtls.sha256)
                A.deep_equal(curl_record.target_ids, { "win32-x86" })
                A.deep_equal(mbedtls_record.target_ids, { "win32-x86" })
                A.equal(SHA256.hex(curl_patch), curl_record.sha256)
                A.equal(SHA256.hex(mbedtls_patch), mbedtls_record.sha256)
                A.deep_equal(
                    manifest.dependencies.curl.downstream_patches,
                    lock.components.curl.downstream_patches
                )
                A.deep_equal(
                    manifest.dependencies.mbedtls.downstream_patches,
                    lock.components.mbedtls.downstream_patches
                )
            end,
        },
        {
            name = "patches change only the audited curl and TLS source files",
            run = function()
                local curl_old, curl_new = patch_files(curl_patch)
                local mbedtls_old, mbedtls_new = patch_files(mbedtls_patch)
                local expected_curl = {
                    "configure", "configure.ac", "lib/curl_setup.h", "lib/easy_lock.h",
                    "lib/curl_threads.h", "lib/curl_threads.c", "lib/rand.c",
                    "lib/curlx/timeval.c", "lib/curlx/fopen.c",
                }
                local expected_mbedtls = {
                    "library/entropy_poll.c", "library/platform.c",
                }
                A.deep_equal(curl_old, expected_curl)
                A.deep_equal(curl_new, expected_curl)
                A.deep_equal(mbedtls_old, expected_mbedtls)
                A.deep_equal(mbedtls_new, expected_mbedtls)
                A.falsy(curl_patch:find("/home/", 1, true))
                A.falsy(mbedtls_patch:find("out/qualification", 1, true))
            end,
        },
        {
            name = "XP additions use CryptoAPI old CRT and synchronous IPv4 guards",
            run = function()
                local curl_added = additions(curl_patch)
                local mbedtls_added = additions(mbedtls_patch)
                for _, marker in ipairs({
                    "The minimum build target is Windows XP (0x0501)",
                    "Windows XP compatibility builds require IPv6 to be disabled",
                    "Windows XP compatibility builds require the synchronous resolver",
                    "InitializeCriticalSection(m)",
                    "CryptAcquireContextW",
                    "CryptGenRandom",
                    "GetTickCount()",
                    "file = freopen(target, mode, fp)",
                }) do
                    A.contains(curl_added, marker)
                end
                for _, marker in ipairs({
                    "#include <wincrypt.h>",
                    "CryptAcquireContextW",
                    "CryptGenRandom",
                    "_WIN32_WINNT >= 0x0600",
                }) do
                    A.contains(mbedtls_added, marker)
                end
                for _, forbidden in ipairs({
                    "BCrypt", "bcrypt.h", "AcquireSRWLockExclusive",
                    "SleepConditionVariableCS",
                    "freopen_s(&file", "mbstowcs_s(", "wcstombs_s(",
                }) do
                    A.falsy(curl_added:find(forbidden, 1, true))
                end
                A.falsy(mbedtls_added:find("BCryptGenRandom(", 1, true))
                A.falsy(mbedtls_added:find("<bcrypt.h>", 1, true))
                A.falsy(mbedtls_added:find("vsnprintf_s(s", 1, true))
            end,
        },
        {
            name = "transport profile keeps verification TLS floor and evidence gate closed",
            run = function()
                local profile = lock.curl_profile
                local xp = profile.target_build_overrides["win32-x86"]
                A.equal(profile.minimum_tls, "TLSv1.2-or-newer")
                A.equal(profile.certificate_verification, "bundled-ca-required")
                A.equal(profile.proxy_certificate_verification, "bundled-ca-required")
                A.equal(xp.win32_winnt, "0x0501")
                A.equal(xp.subsystem_version, "5.01")
                A.equal(xp.resolver, "blocking")
                A.falsy(xp.ipv6)
                A.deep_equal(xp.downstream_patch_components, { "curl", "mbedtls" })
                for _, marker in ipairs({
                    "curl_config_grammar=standalone-no-option",
                    "proxy_tls_floor=TLSv1.2-or-newer-via-mbedtls",
                    "locked curl no-option parser branch is missing",
                    "Mbed TLS protocol floor is not exactly TLS 1.2 and TLS 1.3",
                }) do
                    A.contains(candidate_build, marker)
                end
                A.falsy(lock.release_authorized)
                A.falsy(lock.target_artifacts_qualified)
            end,
        },
        {
            name = "planner rejects patch target source and manifest drift",
            run = function()
                A.truthy(planner_module.new(manifest, lock))

                local wrong_target = clone(lock)
                wrong_target.components.curl.downstream_patches[1].target_ids[1]
                    = "win64-x86_64"
                local target_planner, target_error = planner_module.new(manifest, wrong_target)
                A.falsy(target_planner)
                A.equal(target_error.code, "InvalidDependencyLock")

                local wrong_source = clone(lock)
                wrong_source.components.mbedtls.downstream_patches[1]
                    .applies_to_source_sha256 = string.rep("0", 64)
                local source_planner, source_error = planner_module.new(manifest, wrong_source)
                A.falsy(source_planner)
                A.equal(source_error.code, "InvalidDependencyLock")

                local wrong_manifest = clone(manifest)
                wrong_manifest.dependencies.curl.downstream_patches[1].purpose = "changed"
                local manifest_planner, manifest_error = planner_module.new(
                    wrong_manifest,
                    lock
                )
                A.falsy(manifest_planner)
                A.equal(manifest_error.code, "InvalidReleaseManifest")
            end,
        },
    },
}
