# Coding-readiness machine contracts

Updated: 2026-08-29

This directory is the machine-readable implementation boundary for yaca v0.1. The prose subsystem documents explain intent and rationale; these Lua tables freeze stable IDs, exact sets, mappings, and fixture expectations so the first implementation plan does not invent a second contract.

Contract version: 0.1.0-readiness.1. These files are design inputs, not product runtime modules and not a public API.

## Authority and proof boundary

- Product choices come from D-001 through D-071. D-071 authorizes readiness closeout and discardable proofs, but does not change the selected product guarantees.
- A value marked proof_required or sourced from a TP remains a measured release/implementation constant. A developer must not replace it with an INI/XML field or an unlimited sentinel.
- context.rng plus context.lua form the internal Context schema: RNG owns XML structure; context.lua owns event payload types and cross-event relations.
- CLI projection means a local argv, chat command line, or management-REPL command line. It does not create a daemon, IPC/RPC endpoint, or unattended approval bypass.
- Synthetic fixtures freeze causality and parser behavior. Recorded provider bytes and target-platform observations remain separate technical proof evidence.

## Validation

From the repository root run:

    bin/lua55 .tools/validate_design_contracts.lua

The validator checks 16 contracts and 12 fixture sets: cross-contract identity sets, aliases, state transitions, permission folding, exact format/path hashes, Prompt/control mappings, synthetic provider wire bytes, transport/TUI matrices, Context schema inventory, release pins, implementation task dependencies, diagnostics, and zero-surface rules. When xmllint is available it also validates the minimal Context XML against context.rng.

The phase and whole-program plan have a second validator:

    bin/lua55 .tools/validate_coding_readiness.lua

It requires Gate A/B to be passed, Release Gate R to remain closed, all 28 readiness items to route to one of C01--C34, the plan to contain every file/commit boundary, public documentation to remain honest, and the source inventory to match the explicit `pre-coding` / `implementing` / `implemented-unqualified` phase.

## Files

| File | Owns |
| --- | --- |
| product.lua | three release targets and end-to-end journeys |
| config.lua | exact INI fields, XML whitelist, secret and tightening rules |
| runtime.lua | AgentLoop identities, states, outcomes, controls and transitions |
| actions.lua | argv/chat/REPL semantic action registry |
| tools.lua | eight tools, five capabilities and permission fold |
| model.lua | normalized request/event/response and control mapping |
| context.lua / context.rng | internal XML/event contract |
| tui.lua | prompts, input fallback and renderer states |
| platform.lua | safe loading, identity, lock and filesystem port boundaries |
| diagnostics.lua | stable errors, exits and self-test checks |
| zero_surface.lua | excluded component/action/config/schema/dependency surfaces |
| formats.lua | strict UTF-8, SHA-256/path hash, JSON, SSE, XML and INI semantics |
| transport.lua | process/curl/HTTP/retry/redirect/secret carrier boundary |
| prompts.lua | exact purpose prompts, layer order and native control schemas |
| release.lua | dependency pins, component/module allowlists and candidate constants |
| readiness.lua | Gate A/B/R phases and M0--M10 / C01--C34 execution graph |
| fixtures/ | synthetic golden inputs and traces |
