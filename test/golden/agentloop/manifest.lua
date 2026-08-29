--[=[
File: manifest.lua
Date: 2026-08-29
Author: WaterRun
Description: Golden typed AgentLoop state, control, purpose, and outcome traces.
]=]

return {
    schema_version = "yaca-agentloop-golden-v1",
    traces = {
        ["finish-no-doublecheck"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "Finalizing", "Idle",
            },
            purposes = { "main" },
            controls = { "finish" },
            outcome = "completed",
        },
        ["finish-doublecheck-pass"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "EvaluatingTermination", "Finalizing", "Idle",
            },
            purposes = { "main", "termination-review" },
            controls = { "finish" },
            outcome = "completed",
        },
        ["finish-doublecheck-gap-same-turn"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "EvaluatingTermination", "RequestingModel", "Streaming",
                "Finalizing", "Idle",
            },
            purposes = { "main", "termination-review", "main" },
            controls = { "finish", "finish" },
            outcome = "completed",
        },
        ["ask-user-then-reply"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "WaitingUser", "RequestingModel", "Streaming",
                "Finalizing", "Idle",
            },
            purposes = { "main", "main" },
            controls = { "ask-user", "finish" },
            outcome = "completed",
        },
        ["model-yield-waits"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming", "WaitingUser",
            },
            purposes = { "main" },
            controls = {},
            reported_outcome = "waiting_user",
        },
        ["typed-refuse"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "Finalizing", "Idle",
            },
            purposes = { "main" },
            controls = { "refuse" },
            outcome = "refused",
        },
        ["permission-deny"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "DispatchingTools", "RequestingModel", "Streaming",
                "Finalizing", "Idle",
            },
            purposes = { "main", "main" },
            controls = { "finish" },
            tool_result_kinds = { "synthetic-denied" },
            outcome = "completed",
        },
        ["approval-reject"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "DispatchingTools", "AwaitingApproval", "DispatchingTools",
                "RequestingModel", "Streaming", "WaitingUser",
            },
            purposes = { "main", "main" },
            controls = {},
            tool_result_kinds = { "synthetic-rejected" },
            reported_outcome = "waiting_user",
        },
        ["cancel-streaming"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "Finalizing", "Idle",
            },
            purposes = { "main" },
            controls = {},
            outcome = "cancelled",
        },
        ["unknown-tool-side-effect"] = {
            states = {
                "Idle", "Preparing", "RequestingModel", "Streaming",
                "DispatchingTools", "ExecutingTool", "Finalizing", "Idle",
            },
            purposes = { "main" },
            controls = {},
            tool_result_kinds = { "unknown" },
            outcome = "unknown_side_effect",
        },
    },
}
