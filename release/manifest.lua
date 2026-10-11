--[[
Author: WaterRun
Date: 2026-10-09
File: manifest.lua
Description: Declares the versioned runtime and release assembly manifest.
]]

--- Runtime and release assembly data.
-- This table remains unqualified until all target evidence is complete.
return {
    schema_version = "yaca-release-manifest-v0.1.0",
    product_version = "1.0.0",
    release_state = "unqualified",
    release_authorized = false,
    target_qualification_complete = false,
    dependency_lock = "release/dependencies.lock",

    layout = {
        lua_directory = "src",
        native_directory = "native",
        data_directory = "__yaca__",
        evidence_directory = "release/evidence",
    },

    lua_modules = {
        "backend_linux", "backend_windows", "bundled", "cli", "clock", "compact", "config",
        "context", "diagnostics", "fs", "index", "ini", "json", "main", "model",
        "network", "path", "permission", "platform", "process", "prompt", "runtime",
        "safety", "session", "terminal", "text", "textcodec", "tools", "tui", "xml",
    },
    native_modules = { "yaca_native", "lxp" },
    native_module_filenames = {
        ["win32-x86"] = { yaca_native = "yaca_native.dll", lxp = "lxp.dll" },
        ["win64-x86_64"] = { yaca_native = "yaca_native.dll", lxp = "lxp.dll" },
        ["linux-x86_64"] = { yaca_native = "yaca_native.so", lxp = "lxp.so" },
    },

    load_policy = {
        source = "absolute-release-root-only",
        current_working_directory = false,
        lua_path = false,
        lua_cpath = false,
        lua_init = false,
        user_directories = false,
        system_directories = false,
        dynamic_extension_discovery = false,
    },

    targets = {
        {
            id = "win32-x86", os = "windows", arch = "x86",
            minimum = "Windows XP SP3", executable = "yaca.exe",
            installer = "Install.cmd", archive = "yaca-1.0.0-win32-x86-clean.zip",
            object_format = "PE32-i386", qualification = "pending",
        },
        {
            id = "win64-x86_64", os = "windows", arch = "x86_64",
            minimum = "Windows 7 SP1", executable = "yaca.exe",
            installer = "Install.cmd", archive = "yaca-1.0.0-win64-x86_64-clean.zip",
            object_format = "PE32+-x86-64", qualification = "pending",
        },
        {
            id = "linux-x86_64", os = "linux", arch = "x86_64",
            minimum = "CentOS 7 x86_64", executable = "yaca",
            installer = "Install.sh", archive = "yaca-1.0.0-linux-x86_64-clean.zip",
            object_format = "ELF64-x86-64", qualification = "pending",
        },
    },

    dependencies = {
        luainstaller = {
            version = "1.5.0", tag = "v1.5.0",
            commit = "a289a1b",
            full_commit = "a289a1bed6c6dcf8ad4f11a1d9e28f2f2989adbf",
            downstream_patches = {
                {
                    path = "release/patches/luainstaller-1.5.0-resources.patch",
                    sha256 = "25f5816a67a3d65f4a7ef74c9c744493f626b1aa657fb4b6451cd0bfbeb57443",
                    purpose = "explicit-hash-verified-resource-overlay",
                    applies_to_revision = "a289a1bed6c6dcf8ad4f11a1d9e28f2f2989adbf",
                    base_file_sha256 = {
                        ["src/init.lua"] = "aea35743cbeee546fb7c5128f43a2326425020e5a780f4284f2865e8bd54df1c",
                        ["src/manifest.lua"] = "d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065",
                        ["src/bundler.lua"] = "b8f7fe1a41499c83da8172b935ca9410a9dda3ea7b2a4e87c3ad315afeaf6a17",
                        ["src/onefile.lua"] = "67edbb961affcc496ad99a1bcdd342f07e0a2c488bed6de3442b8ac23e989a68",
                    },
                },
            },
            status = "source-and-patch-pinned-target-artifact-pending",
        },
        lua = {
            version = "5.5.1",
            sha256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce",
            status = "source-pinned-target-artifact-pending",
        },
        expat = {
            version = "2.8.2",
            sha256 = "ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c",
            status = "source-pinned-target-artifact-pending",
        },
        luaexpat = {
            version = "1.5.2",
            sha256 = "89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f",
            status = "source-pinned-target-artifact-pending",
        },
        curl = {
            version = "8.21.0",
            sha256 = "aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6",
            tls_backend = "mbedtls-3.6.7",
            downstream_patches = {
                {
                    path = "release/patches/curl-8.21.0-winxp.patch",
                    sha256 = "8dd8c9d31dca0a5611a88f662bcda56a3531caebd638d63f78ff9ae1ed9c594f",
                    purpose = "restore-win32-xp-static-http-https-compatibility",
                    applies_to_source_sha256 = "aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6",
                    target_ids = { "win32-x86" },
                    base_file_sha256 = {
                        ["configure"] = "236bffd8111d66cb9a17a2e64978718a1ee182fce8f25ef8fc99f56393aa3348",
                        ["configure.ac"] = "44ab8614c3e824b5bbe0e1d0694211dd8fb9c7ac62c47b3f1e8987dea9ed98a8",
                        ["lib/curl_setup.h"] = "8b8233cb31aa58d40965b4d53c428b0e5fc742c041148acbd88bcce5f7ec17cc",
                        ["lib/easy_lock.h"] = "1b3abe3b6ff8d78228e6dffbcf954c38fe05283427a8e7bddaaa37d9caa172af",
                        ["lib/curl_threads.h"] = "6b23757a99b103e600cd9f8f894dfb2d0cb146f24274f77cad692f7f84a613c0",
                        ["lib/curl_threads.c"] = "5233500c2dab55f9a78ca8fab8b134963ff80d8b254f1d3c76bbff2a45927fbc",
                        ["lib/rand.c"] = "d13469813cad22319eb68375d464757e01bb162a9775bce29c2407e6da14a661",
                        ["lib/curlx/timeval.c"] = "c72e3fa44b771af5f9f5f13343d5a28e9183203e783395d1d76289ac3a51504e",
                        ["lib/curlx/fopen.c"] = "ac1ee4422a0e278a41c46173cbd8c0508ec7e382374e968abbf99bf59028116b",
                    },
                },
            },
            status = "source-and-patch-pinned-target-artifact-pending",
        },
        mbedtls = {
            version = "3.6.7",
            sha256 = "a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6",
            downstream_patches = {
                {
                    path = "release/patches/mbedtls-3.6.7-winxp.patch",
                    sha256 = "500c30ccad77f5e33d95c2241b97b6f879dcc1525de6c58b0456fbdd9c6dd4f2",
                    purpose = "restore-win32-xp-entropy-and-crt-compatibility",
                    applies_to_source_sha256 = "a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6",
                    target_ids = { "win32-x86" },
                    base_file_sha256 = {
                        ["library/entropy_poll.c"] = "472e1ba8dfcd751cac88da649987c1422d0e263ffb57ad406bc6652282d48bc4",
                        ["library/platform.c"] = "69f5e0c95478d792ac5654af56817c8272a68c322010e342afacc90e6d57524d",
                    },
                },
            },
            status = "source-and-patch-pinned-target-artifact-pending",
        },
        ca_bundle = {
            version = "2026-08-13",
            sha256 = "f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9",
            status = "source-pinned-target-artifact-pending",
        },
        yaca_native = {
            version = "1.0.0", source = "native/yaca_native.c",
            status = "implemented-target-artifact-pending",
        },
    },

    packaging = {
        editions = { "clean", "std", "full" },
        same_core_for_all_editions = true,
        tool_catalog = "release/tool-bundles.json",
        companion_notices = true,
        builder = "luainstaller-1.5.0",
        builder_mode = "onefile-from-qualified-onedir",
        lua_discovery = "manual-exact-allowlist",
        package_assembly = "explicit-files-only",
        historical_bin_copy = false,
        compression_of_native_inputs = false,
        required_root_entries = {
            windows = { "yaca.exe" },
            linux = { "yaca" },
        },
        shipped_component_allowlist = {
            "launcher+embedded-lua", "yaca-lua-sources", "yaca-native",
            "lxp+static-expat", "curl+static-mbedtls", "ca-bundle",
            "optional-edition-tools",
        },
        forbidden_core_components = {
            "sqlite3", "jq", "7za", "busybox", "file", "iconv", "patch",
            "diff", "python", "ssh", "git", "compiler-toolchain",
        },
        forbidden_shipped_components = {
            "web-server", "browser-assets", "media-codec",
            "speech-runtime", "remote-controller", "plugin-loader", "mcp-client",
            "telemetry-client", "update-client",
        },
        evidence_per_target = {
            "sha256", "component-license-manifest", "SBOM", "build-summary",
            "full-test-summary",
        },
    },

    implementation_candidates = {
        status = "modern-proof-candidates-not-release-frozen",
        minimum_scannable_secret_bytes = 8,
        redirect_maximum = 3,
        retry = {
            identity = "tp006-modern-candidate-v1",
            default_count = 2,
            default_base_delay_ms = 500,
            maximum_count = 10,
            exponent = 2,
            maximum_delay_ms = 30000,
            runtime_wait_cap_ms = 60000,
            deterministic_jitter_permille = 100,
        },
    },

    unresolved_release_constants = {
        "all-runtime-hard-caps", "stuck-detector-thresholds", "curl-version-and-hash",
        "CA-version-and-hash", "process-cancel-grace", "event-poll-and-input-latency",
        "Context-size-and-commit-latency", "Catalog-scan-cap", "TUI-output-backlog-cap",
    },
}
