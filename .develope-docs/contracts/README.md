# Coding-readiness machine contracts

Updated: 2026-08-29

This directory is the machine-readable implementation boundary for yaca v0.1. The prose subsystem documents explain intent and rationale; these Lua tables freeze stable IDs, exact sets, mappings, and fixture expectations so the first implementation plan does not invent a second contract.

Contract version: 0.1.0-readiness.1. These files are design inputs, not product runtime modules and not a public API.

## Authority and proof boundary

- Product choices come from D-001 through D-070. D-071 authorizes readiness closeout and discardable proofs, but does not change the selected product guarantees.
- A value marked proof_required or sourced from a TP remains a measured release/implementation constant. A developer must not replace it with an INI/XML field or an unlimited sentinel.
- context.rng plus context.lua form the internal Context schema: RNG owns XML structure; context.lua owns event payload types and cross-event relations.
- CLI projection means a local argv, chat command line, or management-REPL command line. It does not create a daemon, IPC/RPC endpoint, or unattended approval bypass.
- Synthetic fixtures freeze causality and parser behavior. Recorded provider bytes and target-platform observations remain separate technical proof evidence.

## Validation

From the repository root run:

    bin/lua55 .tools/validate_design_contracts.lua

The validator checks cross-contract identity sets, aliases, state transitions, permission folding, model-control mappings, Context schema inventory, diagnostics dependencies, fixtures, and the zero-surface manifest. When xmllint is available it also validates the minimal Context XML against context.rng.

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
| fixtures/ | synthetic golden inputs and traces |
