--[[
Author: WaterRun
Date: 2026-10-23
File: manifest.lua
Description: Indexes expected versioned purpose prompts and their exact rendered artifacts.
]]

return {
    schema_version = "yaca-prompt-golden-v0.1.0",
    prompt_version = "yaca-prompt-v0.1.0-readiness.6",
    fixture_generation = "generation-7",
    cases = {
        {
            purpose = "main",
            digest = "fe07b1e7a036a6bd34769d2ac3e81d4b5488f20f9aed55174387d1b24500f9e3",
            total_bytes = 2542,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "ask",
            digest = "ff1dd6b891ca404bf6efc5fee4145800fe10596ce2721d4ce2e1cf13faf227db",
            total_bytes = 1900,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "action-review",
            digest = "5e6478cdcee510b5479e1fe5b4207a71dc084685c64a5c7e882a8d88676ba32c",
            total_bytes = 2342,
            kinds = { "runtime-purpose", "global", "model", "permission-quoted", "context-quoted", "proposed-action-quoted", "evidence-quoted" },
        },
        {
            purpose = "termination-review",
            digest = "96ae14b9e2457a542fa407cff40ccdf80c4d2751acd8f94d5b8ca2a992ac2817",
            total_bytes = 2389,
            kinds = { "runtime-purpose", "global", "model", "double-check-goal-quoted", "context-quoted", "candidate-report-quoted", "evidence-quoted" },
        },
        {
            purpose = "compaction",
            digest = "4ea7a254ed322b6b10ddfd23f3be5a3bfd5bbf9cf55221dab3939ee789ede449",
            total_bytes = 1584,
            kinds = { "runtime-purpose", "global", "model", "model-view-input" },
        },
        {
            purpose = "self-test",
            digest = "a0e6ddac6ebc5ab3540bab4871ea3922705fbe057071442a6af2ba67fdca1446",
            total_bytes = 1796,
            kinds = { "runtime-purpose", "global", "model", "synthetic-observation" },
        },
        {
            purpose = "context-name",
            digest = "b92d94ee1fe2224819faf0fa7fd8cf4cd7cf49e69656855555155f403da4ba85",
            total_bytes = 1531,
            kinds = { "runtime-purpose", "global", "model", "committed-facts" },
        },
    },
    controls = {
        version = "yaca-controls-v0.1.0-readiness.1",
        digest = "b88812bd72c0dcf26318f750f74183bc27e853de9ef2632df299a1425557128a",
        canonical_bytes = 768,
        order = { "yaca_finish", "yaca_ask_user", "yaca_refuse" },
    },
}
