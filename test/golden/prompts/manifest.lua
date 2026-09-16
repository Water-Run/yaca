return {
    schema_version = "yaca-prompt-golden-v0.1.0",
    prompt_version = "yaca-prompt-v0.1.0-readiness.3",
    fixture_generation = "generation-7",
    cases = {
        {
            purpose = "main",
            digest = "8bd63145b87d4c8846c4f7aeb361aa7ccee7edfdc1c540992a693625979ba93f",
            total_bytes = 2175,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "side",
            digest = "77611736767c58db2504dab0cfbb08558b8f7e3ee52b108a61c78645c948b51a",
            total_bytes = 1891,
            kinds = { "runtime-purpose", "global", "model", "permission", "context", "user-message" },
        },
        {
            purpose = "action-review",
            digest = "a5729542bf8f6ae35afe261c3a26c8a23aae19147d8ee4d3dcf6940f568e4c4e",
            total_bytes = 2333,
            kinds = { "runtime-purpose", "global", "model", "permission-quoted", "context-quoted", "proposed-action-quoted", "evidence-quoted" },
        },
        {
            purpose = "termination-review",
            digest = "690dfe9a581fddc0eb00f5a5d8b2897d83f40a91cb804e1e8e07717b51004865",
            total_bytes = 2380,
            kinds = { "runtime-purpose", "global", "model", "double-check-goal-quoted", "context-quoted", "candidate-report-quoted", "evidence-quoted" },
        },
        {
            purpose = "compaction",
            digest = "86aaf6d40c43e3fe642e6d1334cbedd4c1ab5687c339bef29bc0c54d4547bf58",
            total_bytes = 1575,
            kinds = { "runtime-purpose", "global", "model", "model-view-input" },
        },
        {
            purpose = "self-test",
            digest = "cdff53d264f826f6ee071508753a0e9b7a566c626b197cc53e2a01e56f1db493",
            total_bytes = 1787,
            kinds = { "runtime-purpose", "global", "model", "synthetic-observation" },
        },
        {
            purpose = "context-name",
            digest = "6037b6eca41a21335efe4c5f65b69688a2b519e747bb3556a1d2b2477072cc27",
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
