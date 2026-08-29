return {
    schema_version = "yaca-prompt-golden-v0.1.0",
    prompt_version = "yaca-prompt-v0.1.0-readiness.2",
    fixture_generation = "generation-7",
    cases = {
        {
            purpose = "main",
            digest = "803221ae47f621080879f897738dc849af4e9a25738cdd8c007edb882ac431b7",
            total_bytes = 2175,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "side",
            digest = "380b85545b80a2ceab5b77a8d621cbf0aabad6dd301ced4596faa08924937dff",
            total_bytes = 1891,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "action-review",
            digest = "f4c26c810442f811dd7a0a03070b45b8fa5b9ca6edc686eecd7d96d9e4fc55c0",
            total_bytes = 2333,
            kinds = { "runtime-purpose", "global", "model", "permission-quoted", "context-quoted", "proposed-action-quoted", "evidence-quoted" },
        },
        {
            purpose = "termination-review",
            digest = "0f13f2d51d1d4dfdbb19c54ec4f22b2158377bf2d8c2c15cd79c9dc8cda467a3",
            total_bytes = 2380,
            kinds = { "runtime-purpose", "global", "model", "double-check-goal-quoted", "context-quoted", "candidate-report-quoted", "evidence-quoted" },
        },
        {
            purpose = "compaction",
            digest = "7c499947d94b6c6caa681677ed584f5d906b86410a8e461130ee0e6c4912bf57",
            total_bytes = 1575,
            kinds = { "runtime-purpose", "global", "model", "model-view-input" },
        },
        {
            purpose = "self-test",
            digest = "408a6488ffc329fd57ea918c509096b774c14b86955b1179d23f5d259dfd7c97",
            total_bytes = 1529,
            kinds = { "runtime-purpose", "global", "model", "synthetic-observation" },
        },
        {
            purpose = "context-name",
            digest = "f6f7ec7a8d00e7ac74b6921a89d7b00a3c6d45ab41149298cb7c1c244a54582f",
            total_bytes = 1522,
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
