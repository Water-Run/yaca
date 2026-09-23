--[[
Author: WaterRun
Date: 2026-09-23
File: manifest.lua
Description: Indexes expected versioned purpose prompts and their exact rendered artifacts.
]]

return {
    schema_version = "yaca-prompt-golden-v0.1.0",
    prompt_version = "yaca-prompt-v0.1.0-readiness.5",
    fixture_generation = "generation-7",
    cases = {
        {
            purpose = "main",
            digest = "8b3749a9ad7244503338bf78d2352ffa23cfabe90da6fc467b2d7cb437ffe6aa",
            total_bytes = 2184,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "ask",
            digest = "2fb42eda32434ca2776ead2a868462d17726d25f84840b14b291b44c89a79247",
            total_bytes = 1900,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "action-review",
            digest = "e9cb959de21038f9acb4c244b911d756dc6cc6d544a6461ac2ca4d522f5778da",
            total_bytes = 2342,
            kinds = { "runtime-purpose", "global", "model", "permission-quoted", "context-quoted", "proposed-action-quoted", "evidence-quoted" },
        },
        {
            purpose = "termination-review",
            digest = "84be47a98206faee20c9fe8d50027fba32dbfd8652435e5bfc0b31c5a73c06ae",
            total_bytes = 2389,
            kinds = { "runtime-purpose", "global", "model", "double-check-goal-quoted", "context-quoted", "candidate-report-quoted", "evidence-quoted" },
        },
        {
            purpose = "compaction",
            digest = "a4d48efaab6e06b36e859ffd56bfcc80f9a4bf8bb1f4f77d2b2d90a6f6a2fc39",
            total_bytes = 1584,
            kinds = { "runtime-purpose", "global", "model", "model-view-input" },
        },
        {
            purpose = "self-test",
            digest = "686dbc0604baff663ae864032c6e9aadbe5a5b87c8b3f85e0ba0024c5eaf6064",
            total_bytes = 1796,
            kinds = { "runtime-purpose", "global", "model", "synthetic-observation" },
        },
        {
            purpose = "context-name",
            digest = "23879ec103df7faccafb3d8467bac5de74d5ef75661746f2d6a7398c92d9998f",
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
