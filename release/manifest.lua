--[[
File: manifest.lua
Date: 2026-08-30
Author: WaterRun
Description: Declares the versioned runtime and release assembly manifest.
]]

--- Runtime and release assembly data.
-- This table remains unqualified until all target evidence is complete.
return {
    schema_version = "yaca-release-manifest-v0.1.0",
    product_version = "0.1.0",
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
        "backend_linux", "backend_windows", "cli", "clock", "compact", "config",
        "context", "diagnostics", "fs", "index", "ini", "json", "main", "model",
        "network", "path", "permission", "platform", "process", "prompt", "runtime",
        "safety", "session", "terminal", "text", "tools", "tui", "xml",
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
            installer = "Install.cmd", archive = "yaca-0.1.0-win32-x86.zip",
            object_format = "PE32-i386", qualification = "pending",
        },
        {
            id = "win64-x86_64", os = "windows", arch = "x86_64",
            minimum = "Windows 7 SP1", executable = "yaca.exe",
            installer = "Install.cmd", archive = "yaca-0.1.0-win64-x86_64.zip",
            object_format = "PE32+-x86-64", qualification = "pending",
        },
        {
            id = "linux-x86_64", os = "linux", arch = "x86_64",
            minimum = "CentOS 7 x86_64", executable = "yaca",
            installer = "Install.sh", archive = "yaca-0.1.0-linux-x86_64.zip",
            object_format = "ELF64-x86-64", qualification = "pending",
        },
    },

    dependencies = {
        luainstaller = {
            version = "1.3.0", tag = "v1.3.0",
            commit = "97192d1",
            full_commit = "97192d100077b31b61dc8f94427e14df1c68a9eb",
            downstream_patches = {
                {
                    path = "release/patches/luainstaller-1.3.0-resources.patch",
                    sha256 = "df011b4a5f54e96a098a2dd235e6a7dc300f7ed7ff7e2a2c269b9b01ff203210",
                    purpose = "explicit-hash-verified-resource-overlay",
                    applies_to_revision = "97192d100077b31b61dc8f94427e14df1c68a9eb",
                    base_file_sha256 = {
                        ["src/init.lua"] = "55694d5e1c349362206e24a3ee8670977e5ea40fd51f0a457b221c95a84fce2d",
                        ["src/manifest.lua"] = "d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065",
                        ["src/bundler.lua"] = "502da4a599ee0565d11d6c58455a1834d3333f31f8c247e6ee8260fb1dafcfae",
                        ["src/onefile.lua"] = "363e9a78d157821be7d6e222a4494c1f65998f5cc920c6f4cfcc0eee01dae610",
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
            status = "source-pinned-target-artifact-pending",
        },
        mbedtls = {
            version = "3.6.7",
            sha256 = "a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6",
            status = "source-pinned-target-artifact-pending",
        },
        ca_bundle = {
            version = "2026-08-13",
            sha256 = "f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9",
            status = "source-pinned-target-artifact-pending",
        },
        yaca_native = {
            version = "0.1.0", source = "native/yaca_native.c",
            status = "implemented-target-artifact-pending",
        },
    },

    packaging = {
        builder = "luainstaller-1.3.0",
        builder_mode = "onefile-from-qualified-onedir",
        lua_discovery = "manual-exact-allowlist",
        package_assembly = "explicit-files-only",
        historical_bin_copy = false,
        compression_of_native_inputs = false,
        required_root_entries = {
            windows = { "yaca.exe", "Install.cmd", "README.txt", "LICENSE", "docs/" },
            linux = { "yaca", "Install.sh", "README.txt", "LICENSE", "docs/" },
        },
        shipped_component_allowlist = {
            "launcher+embedded-lua", "yaca-lua-sources", "yaca-native",
            "lxp+static-expat", "curl+static-mbedtls", "ca-bundle",
            "Install-script", "README.txt", "LICENSE", "docs",
        },
        forbidden_shipped_components = {
            "sqlite3", "jq", "7za", "busybox", "file", "iconv", "patch",
            "diff", "web-server", "browser-assets", "media-codec",
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
