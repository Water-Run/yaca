# Disposable modern-host proofs

These programs validate risky implementation candidates before product coding.
They are not yaca runtime modules, are not shipped, and do not constitute target
qualification for Windows XP/Win32, Win64, or CentOS 7/Linux x86_64.

Run the complete local set from the repository root:

    bash .tools/run_coding_readiness.sh

The individual proofs are:

| Proof | Command | Modern-host claim |
| --- | --- | --- |
| TP-003 | `bin/lua55 .tools/proofs/tp003_event_pump.lua` | Deterministic fake `start/poll/cancel/join/close` ports, bounded/coalescing queue, typed terminal truth, context-name scheduling, and zero excluded workers |
| TP-006 | `python3 .tools/proofs/tp006_curl_carrier.py` | Loopback curl carrier/cancel canary, ambient isolation, retry oracle, exact streaming scanner, and zero excluded purposes |
| TP-008 | `python3 .tools/proofs/tp008_xml_commit.py .develope-docs/contracts/fixtures/context-minimal.xml .develope-docs/contracts/context.rng` | POSIX full-rewrite publication, writer lock, process-crash recovery, rename/rebind recovery, unknown-operation handling, and known-generation deletion |
| TP-010 | `bash .tools/proofs/tp010_build.sh` | Pinned source build of Lua 5.5.1 + Expat 2.8.2 + LuaExpat 1.5.2, static Expat closure, SAX threat corpus, exact UTF-8/XML carrier corpus, and Context chunking |
| RP-001 | `bash .tools/proofs/rp001_resource_overlay.sh` | Exact luainstaller revision and base-file audit, pinned downstream patch application, and hash-verified onedir/onefile resource overlay |

TP-010 downloads only these hash-pinned upstream archives and builds entirely in
a temporary directory. All proof programs remove their temporary state. A PASS
does not freeze target-specific timers, filesystem guarantees, TLS behavior,
resource limits, or conservative Win32 ISA/API choices; those remain explicit
qualification tasks.

RP-001 exports the exact locked luainstaller commit from an adjacent checkout
(or clones the exact tagged revision), verifies every patched base file and the
patch itself, and builds exact Lua 5.5.1 in temporary state. Its PASS remains a
modern Linux packaging proof and is not Windows or CentOS target qualification.
