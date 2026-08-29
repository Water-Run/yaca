return {
    schema_version = "yaca-prompt-golden-v0.1.0",
    prompt_version = "yaca-prompt-v0.1.0-readiness.1",
    fixture_generation = "generation-7",
    cases = {
        {
            purpose = "main",
            digest = "a42f697030932e051fcda34a69eaefa7bec6c5884d998d1b1c7ddd1bf3cc245c",
            total_bytes = 2175,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "side",
            digest = "bab5306a62e5782a0b2fac3a20e19d1a2551d40504ce5e1954d6e92ea6d54047",
            total_bytes = 1891,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "action-review",
            digest = "58ccc3824a81b9c95c4bd0cc4e1c6c86ec5c0b9432f2069e88c26a7cc26c78bd",
            total_bytes = 2161,
            kinds = { "runtime-purpose", "global", "model", "permission-quoted", "context-quoted", "proposed-action-quoted", "evidence-quoted" },
        },
        {
            purpose = "termination-review",
            digest = "d74a0ca1a2453e66ed2e9e98d5fa1fe7fb33851d192083faefdefa2277f60901",
            total_bytes = 2160,
            kinds = { "runtime-purpose", "global", "model", "double-check-goal-quoted", "context-quoted", "candidate-report-quoted", "evidence-quoted" },
        },
        {
            purpose = "compaction",
            digest = "d49dc197f497b3d304f2837167fcefcae860a1c1e122e526665628460388fe1d",
            total_bytes = 1575,
            kinds = { "runtime-purpose", "global", "model", "model-view-input" },
        },
        {
            purpose = "self-test",
            digest = "7306b07a30a74c844996bf513b67262986d86e74e4cea7ce89dbe0a7b92583e2",
            total_bytes = 1529,
            kinds = { "runtime-purpose", "global", "model", "synthetic-observation" },
        },
        {
            purpose = "context-name",
            digest = "afaa494fde5ef9a1911faab39555cfaec55005b557188b4dc7463a9af6a71cb9",
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
