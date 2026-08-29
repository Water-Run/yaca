return {
  evidence_version = "modern-2026-08-29.1",
  observed_at = "2026-08-29",
  design_baseline_commit = "a169dd0",
  host = {
    os = "Fedora Linux 44 (Workstation Edition)",
    kernel = "Linux 7.1.10-200.fc44.x86_64",
    architecture = "x86_64",
  },
  source_pins = {
    lua = {
      version = "5.5.1",
      sha256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce",
      url = "https://www.lua.org/ftp/lua-5.5.1.tar.gz",
    },
    expat = {
      version = "2.8.2",
      sha256 = "ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c",
      url = "https://github.com/libexpat/libexpat/releases/download/R_2_8_2/expat-2.8.2.tar.gz",
    },
    luaexpat = {
      version = "1.5.2",
      sha256 = "89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f",
      url = "https://github.com/lunarmodules/luaexpat/archive/refs/tags/1.5.2.tar.gz",
    },
  },
  proofs = {
    {
      id = "TP-003",
      status = "proven-modern",
      scope = "deterministic-fake-port-core",
      command = "bin/lua55 .tools/proofs/tp003_event_pump.lua",
      assertions = 453,
      source_sha256 = "2133be3a0cfb4e489d5268d2c11beec875f4558c638a9672a9321ba5d914a418",
      target_pending = { "Win32 console/wait adapter", "CentOS wait adapter", "real process/network I/O", "suspend/resume" },
    },
    {
      id = "TP-006",
      status = "proven-modern",
      scope = "loopback-carrier-cancel-retry-scanner",
      command = "python3 .tools/proofs/tp006_curl_carrier.py",
      assertions = 319,
      source_sha256 = "8103e6e0d902526f2fc6068a8baef828a121611538d8b577ca876388109241ff",
      target_pending = { "bundled curl", "XP/CentOS TLS/proxy/CA", "target timer granularity", "integrated redirect controller" },
      candidates_not_release_frozen = {
        minimum_scannable_secret_bytes = 8,
        retry_manifest = "tp006-modern-candidate-v1",
      },
    },
    {
      id = "TP-008",
      status = "proven-modern",
      scope = "linux-posix-publication-recovery",
      command = "python3 .tools/proofs/tp008_xml_commit.py .develope-docs/contracts/fixtures/context-minimal.xml .develope-docs/contracts/context.rng",
      assertions = 321,
      source_sha256 = "a7e4db216d3ed15625eca76dbba0b3119d51158e2ac1478aa51c2c6d9a597566",
      target_pending = { "Windows replace/no-replace", "target filesystem matrix", "power-loss rig", "antivirus/share violations" },
    },
    {
      id = "TP-010",
      status = "proven-modern",
      scope = "linux-x86_64-pinned-source-build-and-corpus",
      command = "bash .tools/proofs/tp010_build.sh",
      assertions = 5564743,
      source_sha256 = {
        build = "6ccda002fba1802349463c3d025341abd22d0cede755784974954122e4a1083c",
        corpus = "11e5ad1953193fa7477401bd197a8ef807ca713ca3944323a043be9fc5f557e2",
      },
      target_pending = { "Win32 x86 build/load", "Win64 build/load", "CentOS 7 runtime", "target resource limits" },
    },
  },
  conclusions = {
    target_qualification_complete = false,
    release_gate_open = false,
    product_source_written = false,
  },
}
