# Modern-host proof evidence — 2026-08-29

Status: TP-003, TP-006, TP-008, and TP-010 have reproducible
`proven-modern` evidence for the scopes below. No result in this directory is
`proven-target`, release qualification, or evidence that the current `bin/`
artifacts are shippable.

The exact machine-readable record is [`manifest.lua`](manifest.lua). The proof
sources live under [`.tools/proofs/`](../../../.tools/proofs/README.md) and the
complete run is:

    bash .tools/run_coding_readiness.sh

## Observation environment

- Design baseline before adding the proof pack: `a169dd0`.
- Fedora Linux 44 Workstation, Linux `7.1.10-200.fc44.x86_64`, x86_64.
- GCC 16.2.1, curl 8.18.0, xmllint/libxml 2.12.10.
- Repository Lua runner: Lua 5.5.0 for contract/TP-003 checks.
- TP-010 isolated build: Lua 5.5.1, Expat 2.8.2, LuaExpat 1.5.2 from the pinned hashes in the manifest.

## Result summary

| Proof | Modern result | What passed | What remains target-only |
| --- | --- | --- | --- |
| TP-003 | PASS, 453 assertions | five-method fake ports; bounded queue; progress coalescing; non-dropped typed terminal outcomes; one-tick cancel observation; context-name marker/baseline/priority/exit; zero excluded workers | Real Win32/XP and CentOS console/process/network wait adapters, suspend/resume, wall-time budgets |
| TP-006 | PASS, 319 assertions | Key through anonymous curl config stdin; body through 0600 no-replace temp; argv/env/temp/stderr canary scan; malicious `.curlrc` disabled; ambient proxy/CA/netrc allowlist; cancel after first SSE event with one attempt; retry/scanner oracle; zero excluded request purposes | Bundled target curl, old TLS/proxy/CA, actual target timer/jitter vectors, redirect-controller integration, endpoint matrix |
| TP-008 | PASS, 321 assertions | 11 ordinary commit, 10 manual-rename, and 10 rebind crash hooks; validated old/new recovery; directory fsync; second-writer lock conflict; Linux `EXDEV`; unknown without replay; four known delete targets | Windows primitives, NTFS/FAT/share/AV behavior, physical power-loss and full filesystem matrix |
| TP-010 | PASS, 5,564,743 Lua assertions | hash-pinned ELF64 build; static Expat/no RPATH; 1,556 Context split positions; DTD/entity/XInclude/resource-limit rejection; every Unicode scalar; 256 binary octets; invalid UTF-8; 952 field split round-trips; zero excluded XML elements | Win32 x86/Win64 builds, CentOS 7 runtime, target-specific memory/latency limits and final package closure |

## Normalized successful output

```text
design-contract validation PASS: 4260 assertions across 11 contracts and 6 fixture sets
proof-evidence validation PASS: 52 assertions across 4 modern proofs

proof=TP-003
scope=modern-host-deterministic-fake-ports
lua=Lua 5.5
queue_peak=7/8
progress_coalesced=27
cancel_latency_ticks=1
terminal_outcomes=completed,cancelled,failed,unknown
context_name=started:2,cancelled:2,disabled_cost:0,exit_joins:0
worker_registry=registered:7,excluded_hits:0
assertions=453
status=PASS

proof=TP-006
scope=modern-host-loopback-and-deterministic-fixtures
curl=curl 8.18.0 (x86_64-redhat-linux-gnu)
secret_carrier=config-stdin
body_carrier=private-no-replace-temp
ambient_config=disabled-and-environment-allowlisted
ambient_parent_variables_observed=10
attempts=echo:1,sse_cancel:1
retry_manifest=tp006-modern-candidate-v1
retry_vector_sha256=7b00c07933eceb36f6157ef25e33c0a321bf43df0e316a53b1435d69ffa0dca0
minimum_scannable_secret_bytes_candidate=8
scanner=max_tail:16,ineligible_short:1,union_sha256:f34cfb335aadc4667778d59749d43715252ef1ae42ccae3441b6aa13e47138b6
request_purposes=registered:7,excluded_hits:0
assertions=319
status=PASS

proof=TP-008
scope=modern-linux-posix-publication-and-recovery
publication=full-rewrite+validate+previous-valid+atomic-replace+directory-fsync
commit_fault_hooks=11
manual_rename_fault_hooks=10
workspace_rebind_fault_hooks=10
writer_lock=second-writer-conflict
cross_device_no_replace=EXDEV
unknown_recovery=unknown:1,auto_replayed:0
permanent_delete_known_targets=4
published_generation_sha256=57cef05ae088c3cbf3f658c626e77560e535a177185c7c8f0d2d26abc611948f
assertions=321
status=PASS

proof=TP-010
scope=modern-linux-pinned-source-build-and-corpus
host=Linux 7.1.10-200.fc44.x86_64 x86_64
compiler=gcc (GCC) 16.2.1 20260819 (Red Hat 16.2.1-2)
source_lua=5.5.1 sha256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
source_expat=2.8.2 sha256=ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
source_luaexpat=1.5.2 sha256=89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f
abi=lua:ELF64,lxp:ELF64,expat:static,no-rpath
lua_runtime=Lua 5.5
luaexpat=LuaExpat 1.5.2
expat=expat_2.8.2
parser=context_split_positions:1556,external_entity_callbacks:0
unicode_scalars=total:1112064,text:1112032,base64:32
binary_octets=256
invalid_utf8_cases=12
field_split_roundtrips=952
zero_surface_hits=0
lua_assertions=5564743
status=PASS
```

The full curl version line is intentionally shortened here; the executable
prints it on every reproduction. Runtime canary values are intentionally never
printed or retained.
