--[[
File: cli.lua
Date: 2026-08-29
Author: WaterRun
Description: Generates CLI projections from the frozen semantic action registry.
]]

local json = require("json")
local text = require("text")

local M = {}

local function failure(code, message, extra)
    local result = { code = code, message = message }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function argument(name, type_name, required, extra)
    local value = { name = name, type = type_name, required = required }
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end

local function argv(long, short, slash, extra)
    local value = { kind = "argv", long = long, short = short, slash = slash }
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end

local function chat(command, key, extra)
    local value = { kind = "chat-line", command = command, key = key }
    for field, item in pairs(extra or {}) do value[field] = item end
    return value
end

local function context_repl(command, extra)
    local value = { kind = "context-repl-line", command = command }
    for field, item in pairs(extra or {}) do value[field] = item end
    return value
end

local function action(id, surface, args, projections, tty, confirm, states, results,
        summary, extra)
    local value = {
        id = id,
        surface = surface,
        args = args,
        projections = projections,
        tty = tty,
        confirm = confirm,
        allowed_states = states,
        results = results,
        summary = summary,
    }
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end

local PRE_RUNTIME = { "pre-runtime" }
local REPL_STATE = { "repl" }
local CHAT_ACTIVE = {
    "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools",
    "AwaitingApproval", "ExecutingTool", "EvaluatingAction",
    "EvaluatingTermination", "WaitingUser",
}
local CHAT_BUSY = {
    "Preparing", "RequestingModel", "Streaming", "DispatchingTools",
    "AwaitingApproval", "ExecutingTool", "EvaluatingAction",
    "EvaluatingTermination", "WaitingUser",
}
local CHAT_MUTABLE = {
    "Idle", "WaitingUser", "Preparing", "RequestingModel", "Streaming",
    "DispatchingTools", "AwaitingApproval", "ExecutingTool",
    "EvaluatingAction", "EvaluatingTermination",
}

local ACTIONS = {
    action("run-chat", "top", {
        argument("directory", "existing-directory", false, { default = "." }),
    }, {
        argv(false, false, false, { positional = true, default_action = true }),
    }, "tty-required", "none", PRE_RUNTIME, { "started", "error" },
    "Start a new unsaved chat draft in an existing directory.", {
        overview_usage = "yaca [directory]",
    }),
    action("help", "top", {
        argument("topic", "string", false),
    }, {
        argv("--help", "-h", "/h"),
    }, "any", "none", PRE_RUNTIME, { "success", "usage" },
    "Show registry-generated help without loading configuration.", {
        non_tty = "allowed", overview_usage = "yaca --help [topic]",
    }),
    action("version", "top", {}, {
        argv("--version", "-v", "/v"),
    }, "any", "none", PRE_RUNTIME, { "success" },
    "Show product, version, and release-target identity.", {
        non_tty = "allowed", overview_usage = "yaca --version",
    }),
    action("self-test", "top", {
        argument("through_stage", "enum:1|2|3", false, {
            default = 1, spelling = "--through-stage",
        }),
        argument("list_checks", "bool", false, {
            default = false, spelling = "--list-checks",
        }),
        argument("excluded_models", "string-list", false, {
            spelling = "--exclude-model", repeatable = true,
        }),
        argument("excluded_checks", "check-id-list", false, {
            spelling = "--exclude-check", repeatable = true,
        }),
        argument("selected_checks", "check-id-list", false, {
            spelling = "--check", repeatable = true,
        }),
        argument("online_consent", "bool", false, {
            spelling = "--i-accept-online-self-test",
        }),
    }, {
        argv("--self-test", "-st", "/st"),
    }, "any", "online-consent-stage2-plus", PRE_RUNTIME,
    { "passed", "partial", "cancelled", "error" },
    "Run ordered diagnostics through Stage 1, 2, or 3.", {
        non_tty = "through-stage-1-offline-only",
        overview_usage = "yaca --self-test [options]",
    }),
    action("model-repl", "top", {}, {
        argv("--model-repl", "-mr", "/mr"),
    }, "tty-required", "inside-repl", PRE_RUNTIME,
    { "success", "cancelled", "error" },
    "Open the offline-safe Model management REPL.", {
        overview_usage = "yaca --model-repl",
    }),
    action("config-repl", "top", {}, {
        argv("--config-repl", "-cfg", "/cfg"),
    }, "tty-required", "inside-repl", PRE_RUNTIME,
    { "success", "cancelled", "error" },
    "Open the offline-safe configuration REPL.", {
        overview_usage = "yaca --config-repl",
    }),
    action("context-repl", "top", {
        argument("view", "enum:recent|full", true),
    }, {
        argv("--context-repl", "-ctx", "/ctx"),
    }, "tty-required", "inside-repl", PRE_RUNTIME,
    { "success", "cancelled", "error" },
    "Open the Context browser in recent or full view.", {
        overview_usage = "yaca --context-repl recent|full",
    }),
    action("continue", "top", {
        argument("selector", "context-selector", true),
    }, {
        argv("--continue", "-c", "/c"),
    }, "tty-required", "none", PRE_RUNTIME,
    { "started", "not-found", "lock-conflict", "error" },
    "Continue one Context selected by short name or precise hash.", {
        overview_usage = "yaca --continue <selector>",
    }),
    action("export-context", "both", {
        argument("selector", "context-selector", false),
    }, {
        argv("--export", "-ex", "/ex"),
        context_repl("export <selector?>"),
    }, "tty-required", "none", { "pre-runtime", "Idle", "WaitingUser" },
    { "success", "not-found", "error" },
    "Export a selected or current Context through the public format.", {
        overview_usage = "yaca --export [selector]",
    }),
    action("status", "top", {}, {
        argv("--status", "-stt", "/stt"),
    }, "tty-required", "none", PRE_RUNTIME, { "success", "error" },
    "Show status for the explicitly opened current Context.", {
        overview_usage = "yaca --status",
    }),

    action("queue-add", "chat", {
        argument("message", "bounded-utf8-text", true),
    }, {
        chat(".queue <message>", "Enter-when-busy", { parse_priority = 20 }),
    }, "tty-required", "none", CHAT_ACTIVE,
    { "started-main", "queued", "queue-full", "error" },
    "Submit the main message or append it to the bounded queue."),
    action("queue-list", "chat", {}, {
        chat(".queue list", false, { parse_priority = 10 }),
    }, "tty-required", "none", CHAT_ACTIVE, { "success" },
    "List queued messages and stable queue IDs."),
    action("queue-delete", "chat", {
        argument("queue_id", "queue-id:#N", true),
    }, {
        chat(".queue delete <#N>", false, { parse_priority = 10 }),
    }, "tty-required", "none", CHAT_ACTIVE,
    { "success", "not-found", "error" },
    "Delete a queued message that has not started."),
    action("queue-move", "chat", {
        argument("from", "queue-id:#N", true),
        argument("to", "queue-position:#N", true),
    }, {
        chat(".queue move <from> <to>", false, { parse_priority = 10 }),
    }, "tty-required", "none", CHAT_ACTIVE,
    { "success", "not-found", "error" },
    "Move a queued message to another queue position."),
    action("queue-edit", "chat", {
        argument("queue_id", "queue-id:#N", true),
        argument("message", "bounded-utf8-text", true),
    }, {
        chat(".queue edit <#N> <message>", false, { parse_priority = 10 }),
    }, "tty-required", "none", CHAT_ACTIVE,
    { "success", "not-found", "error" },
    "Edit a queued message that has not started."),
    action("queue-clear", "chat", {}, {
        chat(".queue clear", false, { parse_priority = 10 }),
    }, "tty-required", "none", CHAT_ACTIVE, { "success" },
    "Clear queued messages that have not started."),
    action("steer", "chat", {
        argument("message", "bounded-utf8-text", true),
    }, {
        chat(".immediate <message>", "Ctrl+Enter"),
    }, "tty-required", "none", CHAT_BUSY,
    { "accepted", "cancel-pending", "unknown-side-effect", "error" },
    "Steer the current active work at its next safe boundary."),
    action("side", "chat", {
        argument("message", "bounded-utf8-text", true),
    }, {
        chat(".side <message>", "Alt+Enter"),
    }, "tty-required", "none", CHAT_ACTIVE,
    { "accepted", "side-busy", "error" },
    "Start one bounded read-only side question."),
    action("multiline", "chat", {}, {
        chat(".multiline", "Shift+Enter"),
    }, "tty-required", "none", CHAT_ACTIVE,
    { "input-mode-entered", "error" },
    "Enter explicit multiline input mode."),
    action("cancel", "chat", {}, {
        chat(".cancel", "Esc"),
    }, "tty-required", "none", CHAT_BUSY,
    { "cancel-requested", "cancelled", "unknown-side-effect", "not-cancellable" },
    "Cancel the innermost cancellable activity."),
    action("cautious", "chat", {
        argument("operation", "enum:status|on|off|toggle|reset", false, {
            default = "status",
        }),
    }, {
        chat(".cautious [on|off|toggle|reset]", false),
    }, "tty-required", "none", CHAT_MUTABLE,
    { "success", "next-turn", "error" },
    "Inspect or change the current Context DoubleCheck override."),
    action("select-model", "chat", {
        argument("selector", "model-selector", false),
    }, {
        chat(".model [selector]", false),
    }, "tty-required", "cross-endpoint-disclosure-if-needed", CHAT_MUTABLE,
    { "success", "next-turn", "not-found", "error" },
    "Select an enabled Model or open the Model selector."),
    action("select-context", "chat", {
        argument("selector", "context-selector", false),
    }, {
        chat(".context [selector]", false),
        context_repl("select <selector>", { required_args = { selector = true } }),
    }, "tty-required", "safe-close-current", { "Idle", "WaitingUser" },
    { "success", "not-found", "lock-conflict", "error" },
    "Select a Context through the shared Resolver."),
    action("status-chat", "chat", {}, {
        chat(".status", false),
    }, "tty-required", "none", {
        "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools",
        "AwaitingApproval", "ExecutingTool", "EvaluatingAction",
        "EvaluatingTermination", "WaitingUser", "Finalizing", "Closing",
    }, { "success" }, "Show the current Context and activity status."),
    action("help-chat", "chat", {
        argument("topic", "string", false),
    }, {
        chat(".help [topic]", false),
    }, "tty-required", "none", CHAT_ACTIVE, { "success", "not-found" },
    "Show registry-generated chat help."),
    action("details", "chat", {
        argument("error_id", "error-instance-id", false),
    }, {
        chat(".details [id]", false),
    }, "tty-required", "none", CHAT_ACTIVE, { "success", "not-found" },
    "Show bounded safe details for an error instance."),
    action("prompt-edit", "chat", {
        argument("operation", "enum:show|set|clear|edit", false, {
            default = "show",
        }),
        argument("text", "bounded-utf8-text", false),
    }, {
        chat(".prompt [show|set|clear|edit] [text]", false),
    }, "tty-required", "editor-if-edit", CHAT_MUTABLE,
    { "success", "next-turn", "error" },
    "Inspect or stage a ContextPrompt change."),
    action("compact-manual", "chat", {}, {
        chat(".compact", false),
    }, "tty-required", "none", { "Idle", "WaitingUser" },
    { "accepted", "no-benefit", "error" },
    "Request bounded manual Context compaction."),
    action("quit", "chat", {}, {
        chat(".quit", false),
    }, "tty-required", "none", {
        "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools",
        "AwaitingApproval", "ExecutingTool", "EvaluatingAction",
        "EvaluatingTermination", "WaitingUser", "Finalizing",
    }, { "closing" }, "Begin graceful close."),

    action("context-list", "context-repl", {
        argument("view", "enum:recent|full", false, { default = "recent" }),
    }, {
        context_repl("list [recent|full]"),
    }, "tty-required", "none", REPL_STATE,
    { "success", "partial", "error" },
    "List a deterministic Context Catalog snapshot."),
    action("context-inspect", "context-repl", {
        argument("selector", "context-selector", true),
    }, {
        context_repl("inspect <selector>"),
    }, "tty-required", "none", REPL_STATE,
    { "success", "busy-metadata-only", "not-found", "error" },
    "Inspect one Context or its allowed busy metadata."),
    action("context-search", "context-repl", {
        argument("query", "bounded-utf8-text", true),
    }, {
        context_repl("search <query>"),
    }, "tty-required", "none", REPL_STATE,
    { "success", "partial", "error" },
    "Search the current bounded Catalog snapshot."),
    action("context-rename", "context-repl", {
        argument("selector", "context-selector", true),
        argument("new_name", "context-name", true),
    }, {
        context_repl("rename <selector> <new-name>"),
    }, "tty-required", "none", REPL_STATE,
    { "success", "destination-exists", "lock-conflict", "target-changed", "error" },
    "Reverify and rename one Context without replacement."),
    action("context-rebind", "context-repl", {
        argument("selector", "context-selector", true),
        argument("target_root", "existing-directory", true),
    }, {
        context_repl("rebind <selector> <target-root>"),
    }, "tty-required", "human-or-explicit-yes", REPL_STATE,
    { "success", "destination-exists", "lock-conflict", "target-changed", "error" },
    "Reverify and bind one Context to another existing root."),
    action("context-delete", "context-repl", {
        argument("selector", "context-selector", true),
        argument("yes", "bool", false, { spelling = "--yes" }),
    }, {
        context_repl("delete <selector> [--yes]"),
    }, "tty-required", "human-or-explicit-yes", { "repl", "pre-runtime" },
    { "success", "lock-conflict", "target-changed", "cancelled", "error" },
    "Permanently delete one reverified Context."),
    action("context-set-auto-rename-disabled", "context-repl", {
        argument("selector", "context-selector", true),
        argument("value", "bool", true),
    }, {
        context_repl("set-auto-rename-disabled <selector> <true|false>"),
    }, "tty-required", "none", REPL_STATE,
    { "success", "lock-conflict", "target-changed", "error" },
    "Set the dedicated AutoRenameDisabled metadata value."),
    action("context-import", "context-repl", {
        argument("path", "existing-context-xml-in-place", true),
    }, {
        context_repl("import <in-place-xml-path>"),
    }, "tty-required", "mapping-and-write-consent", REPL_STATE,
    { "validated-readonly", "mapped", "lock-conflict", "error" },
    "Validate and explicitly map an in-place Context XML file."),
    action("context-repair", "context-repl", {
        argument("selector", "context-selector", true),
    }, {
        context_repl("repair <selector>"),
    }, "tty-required", "typed-plan-confirm", REPL_STATE,
    { "success", "no-safe-repair", "lock-conflict", "cancelled", "error" },
    "Preview and confirm a bounded safe Context repair plan."),
    action("context-refresh", "context-repl", {}, {
        context_repl("refresh"),
    }, "tty-required", "none", REPL_STATE,
    { "success", "partial", "error" },
    "Refresh the bounded Context Catalog snapshot."),
}

local REGISTRY = {
    contract_version = "0.1.0-readiness.1",
    decision_refs = { "D-054", "D-061", "D-062", "D-064", "D-065", "D-066", "D-068" },
    parser = {
        canonical_long_prefix = "--",
        end_of_options = "--",
        slash_alias_platform = "windows-only",
        linux_slash_is_path = true,
        long_name_is_documented_name = true,
        legacy_aliases = {},
        global_modifiers = { "--machine" },
        machine_modifier_consumes_primary_action = false,
    },
    exit_classes = {
        success = 0,
        general_error = 1,
        usage = 2,
        invalid_config = 3,
        lock_conflict = 4,
        interaction_required = 5,
        resolver_negative = 6,
        cancelled = 7,
    },
    machine_output = {
        decision_refs = { "TU-13=A", "TU-21=A", "TU-23=A" },
        schema_version = "yaca-cli-v0.1.0",
        supported_actions = { "help", "version", "self-test" },
        self_test_constraint = "through-stage-1-offline-only",
        stdin = "never-read-in-v0.1",
        stdout = "utf8-machine-payload-only",
        stderr = "bounded-safe-diagnostics-only",
        selection = "explicit-double-dash-machine-only-never-by-redirection",
        single_result = {
            framing = "one-RFC8259-object",
            required_fields = { "schema_version", "kind", "outcome" },
        },
        stream = {
            framing = "JSONL-one-RFC8259-object-per-line",
            required_fields = { "schema_version", "kind", "sequence", "final" },
            final_record_requires = { "outcome" },
            sequence_starts_at = 1,
            sequence_is_contiguous = true,
        },
        ansi = false,
        broken_stdout = "typed-close-never-success",
    },
    fd_mode_matrix = {
        facts = {
            "stdin_is_tty", "stdout_is_tty", "stderr_is_tty", "machine_requested",
        },
        cases = {
            {
                id = "interactive", stdin_is_tty = true, stdout_is_tty = true,
                stderr_is_tty = "any", machine_requested = false,
                result = "human-interactive",
            },
            {
                id = "interactive-stdout-redirected", stdin_is_tty = true,
                stdout_is_tty = false, stderr_is_tty = "any",
                machine_requested = false, result = "TtyRequired",
            },
            {
                id = "interactive-stdin-redirected", stdin_is_tty = false,
                stdout_is_tty = true, stderr_is_tty = "any",
                machine_requested = false, result = "TtyRequired",
            },
            {
                id = "human-noninteractive", stdin_is_tty = "any",
                stdout_is_tty = "any", stderr_is_tty = "any",
                machine_requested = false,
                action_set = { "help", "version", "self-test-stage1" },
                result = "human-text",
            },
            {
                id = "machine-supported", stdin_is_tty = "any",
                stdout_is_tty = "any", stderr_is_tty = "any",
                machine_requested = true,
                action_set = { "help", "version", "self-test-stage1" },
                result = "machine-json-or-jsonl",
            },
            {
                id = "machine-unsupported", stdin_is_tty = "any",
                stdout_is_tty = "any", stderr_is_tty = "any",
                machine_requested = true, result = "UsageError",
            },
        },
    },
    actions = ACTIONS,
}

local ERROR_EXIT_CLASS = {
    UsageError = "usage",
    ConfigMissing = "invalid_config",
    ConfigInvalid = "invalid_config",
    ConfigChanged = "invalid_config",
    ModelUnavailable = "invalid_config",
    PermissionUnavailable = "invalid_config",
    TtyRequired = "interaction_required",
    OnlineConsentRequired = "interaction_required",
    WorkspaceConfirmationRequired = "interaction_required",
    ApprovalRequired = "interaction_required",
    ApprovalStale = "interaction_required",
    NotFound = "resolver_negative",
    HashCollision = "resolver_negative",
    MatchedUnavailable = "resolver_negative",
    ScanIncomplete = "resolver_negative",
    ScanLimit = "resolver_negative",
    LockConflict = "lock_conflict",
    Cancelled = "cancelled",
    ToolCancelled = "cancelled",
}

for _, id in ipairs({
    "TargetChanged", "OpenConflict", "ContextRecoveryRequired",
    "DestinationExists", "UnsupportedPath",
    "UnsupportedObject", "PathEscapesWorkspace", "PermissionDenied",
    "ToolSchemaInvalid", "ToolFailed", "ToolUnknown", "ProcessTimeout",
    "NetworkError", "ProtocolError", "StorageError", "ContextCorrupt",
    "ContextVersionUnsupported", "ContextHardLimit", "ContextStale",
    "BudgetExhausted", "Stuck", "InternalError", "BrokenStdout",
}) do
    ERROR_EXIT_CLASS[id] = "general_error"
end

local OUTCOME_EXIT_CLASS = {
    usage = "usage",
    ["not-found"] = "resolver_negative",
    ["lock-conflict"] = "lock_conflict",
    cancelled = "cancelled",
    partial = "general_error",
    error = "general_error",
    ["queue-full"] = "general_error",
    ["unknown-side-effect"] = "general_error",
    ["side-busy"] = "general_error",
    ["not-cancellable"] = "general_error",
    ["destination-exists"] = "general_error",
    ["target-changed"] = "general_error",
    ["no-safe-repair"] = "general_error",
}

for _, descriptor in ipairs(ACTIONS) do
    for _, outcome in ipairs(descriptor.results) do
        if OUTCOME_EXIT_CLASS[outcome] == nil then
            OUTCOME_EXIT_CLASS[outcome] = "success"
        end
    end
end
OUTCOME_EXIT_CLASS.ready = "success"

REGISTRY.error_exit_classes = ERROR_EXIT_CLASS
REGISTRY.outcome_exit_classes = OUTCOME_EXIT_CLASS

local MACHINE_SUPPORTED = {}
for _, id in ipairs(REGISTRY.machine_output.supported_actions) do
    MACHINE_SUPPORTED[id] = true
end

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[deep_copy(key, seen)] = deep_copy(item, seen) end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

local ACTION_BY_ID = {}
local ARGV_LONG = {}
local ARGV_SHORT = {}
local ARGV_SLASH = {}
local LINE_PROJECTIONS = { ["chat-line"] = {}, ["context-repl-line"] = {} }

local function line_literal(command)
    local angle = command:find("<", 1, true)
    local square = command:find("[", 1, true)
    local marker = angle
    if square and (not marker or square < marker) then marker = square end
    if not marker then return command end
    return command:sub(1, marker - 1):gsub("%s+$", "")
end

local function index_alias(index, token, descriptor)
    if token == false or token == nil then return end
    if index[token] then error("duplicate CLI alias: " .. token) end
    index[token] = descriptor
end

for _, descriptor in ipairs(ACTIONS) do
    if ACTION_BY_ID[descriptor.id] then error("duplicate semantic action: " .. descriptor.id) end
    ACTION_BY_ID[descriptor.id] = descriptor
    for _, projection in ipairs(descriptor.projections) do
        if projection.kind == "argv" then
            index_alias(ARGV_LONG, projection.long, descriptor)
            index_alias(ARGV_SHORT, projection.short, descriptor)
            index_alias(ARGV_SLASH, projection.slash, descriptor)
        else
            local indexed = {
                action = descriptor,
                projection = projection,
                literal = line_literal(projection.command),
            }
            local list = LINE_PROJECTIONS[projection.kind]
            if not list then error("unknown action projection: " .. tostring(projection.kind)) end
            list[#list + 1] = indexed
        end
    end
end
if #ACTIONS ~= 39 then error("semantic action registry must contain exactly 39 actions") end

for _, projections in pairs(LINE_PROJECTIONS) do
    table.sort(projections, function(left, right)
        local left_priority = left.projection.parse_priority or 50
        local right_priority = right.projection.parse_priority or 50
        if left_priority ~= right_priority then return left_priority < right_priority end
        if #left.literal ~= #right.literal then return #left.literal > #right.literal end
        return left.action.id < right.action.id
    end)
end

local function valid_utf8_string(value)
    if type(value) ~= "string" then return false end
    local valid, metadata = text.validate_utf8(value)
    return valid == true and metadata.contains_nul == false
end

local function dense_string_array(values)
    if type(values) ~= "table" then
        return nil, failure("UsageError", "argv must be a dense array of UTF-8 strings")
    end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then
            return nil, failure("UsageError", "argv must be a dense array of UTF-8 strings")
        end
        count = count + 1
    end
    local result = {}
    for index = 1, count do
        if not valid_utf8_string(values[index]) then
            return nil, failure("UsageError", "argv must be a dense array of UTF-8 strings")
        end
        result[index] = values[index]
    end
    return result
end

local function enum_values(type_name)
    local source = type_name:match("^enum:(.+)$")
    if not source then return nil end
    local values = {}
    for value in source:gmatch("[^|]+") do values[value] = true end
    return values
end

local function validate_scalar(specification, value)
    if type(value) ~= "string" or value == "" then
        return nil, "value is empty"
    end
    local valid, validation_error = text.validate_utf8(value)
    if not valid then return nil, validation_error.message end
    local choices = enum_values(specification.type)
    if choices then
        if not choices[value] then return nil, "value is outside the enum" end
        if value:match("^[0-9]+$") then return tonumber(value) end
        return value
    end
    if specification.type == "bool" then
        if value == "true" then return true end
        if value == "false" then return false end
        return nil, "boolean value must be true or false"
    end
    if specification.type == "queue-id:#N"
        or specification.type == "queue-position:#N"
    then
        if not value:match("^#[1-9][0-9]*$") then
            return nil, "queue value must use #N with N greater than zero"
        end
    end
    return value
end

local function usage(message, action_id, argument_name)
    local extra = {}
    if action_id then extra.action = action_id end
    if argument_name then extra.argument = argument_name end
    return failure("UsageError", message, extra)
end

local function apply_defaults(descriptor, request)
    for _, specification in ipairs(descriptor.args) do
        if request[specification.name] == nil and specification.default ~= nil then
            request[specification.name] = deep_copy(specification.default)
        end
    end
end

local function named_argument_map(descriptor)
    local result = {}
    for _, specification in ipairs(descriptor.args) do
        if specification.spelling then result[specification.spelling] = specification end
    end
    return result
end

local function positional_arguments(descriptor)
    local result = {}
    for _, specification in ipairs(descriptor.args) do
        if not specification.spelling then result[#result + 1] = specification end
    end
    return result
end

local function assign_positionals(descriptor, request, values, required_overrides)
    local specifications = positional_arguments(descriptor)
    if #values > #specifications then
        return nil, usage("too many positional arguments", descriptor.id)
    end
    for index, value in ipairs(values) do
        local specification = specifications[index]
        local admitted, validation_error = validate_scalar(specification, value)
        if admitted == nil then
            return nil, usage(
                "invalid " .. specification.name .. ": " .. validation_error,
                descriptor.id,
                specification.name
            )
        end
        request[specification.name] = admitted
    end
    apply_defaults(descriptor, request)
    for _, specification in ipairs(specifications) do
        local required = specification.required
            or (required_overrides and required_overrides[specification.name])
        if required and request[specification.name] == nil then
            return nil, usage(
                "missing required argument " .. specification.name,
                descriptor.id,
                specification.name
            )
        end
    end
    return request
end

local function normalize_facts(facts, request)
    if facts == nil then
        return nil, failure("InvalidCliFacts", "file descriptor facts are required")
    end
    if type(facts) ~= "table" then
        return nil, failure("InvalidCliFacts", "file descriptor facts must be a table")
    end
    local allowed = {
        tty = true,
        stdin_is_tty = true,
        stdout_is_tty = true,
        stderr_is_tty = true,
        machine_requested = true,
    }
    for key in pairs(facts) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidCliFacts", "file descriptor facts contain an unknown field")
        end
    end
    local stdin_is_tty = facts.stdin_is_tty
    local stdout_is_tty = facts.stdout_is_tty
    local stderr_is_tty = facts.stderr_is_tty
    if facts.tty ~= nil then
        if type(facts.tty) ~= "boolean"
            or stdin_is_tty ~= nil or stdout_is_tty ~= nil or stderr_is_tty ~= nil
        then
            return nil, failure("InvalidCliFacts", "tty shorthand conflicts with fd facts")
        end
        stdin_is_tty, stdout_is_tty, stderr_is_tty = facts.tty, facts.tty, facts.tty
    end
    if type(stdin_is_tty) ~= "boolean"
        or type(stdout_is_tty) ~= "boolean"
        or type(stderr_is_tty) ~= "boolean"
    then
        return nil, failure("InvalidCliFacts", "stdin, stdout, and stderr TTY facts are required")
    end
    if facts.machine_requested ~= nil
        and (type(facts.machine_requested) ~= "boolean"
            or facts.machine_requested ~= (request.machine == true))
    then
        return nil, failure(
            "InvalidCliFacts",
            "machine_requested must match the explicit argv modifier"
        )
    end
    return {
        stdin_is_tty = stdin_is_tty,
        stdout_is_tty = stdout_is_tty,
        stderr_is_tty = stderr_is_tty,
    }
end

local function fd_mode(request, facts)
    if type(request) ~= "table" or type(request.id) ~= "string" then
        return nil, usage("a semantic action is required")
    end
    local descriptor = ACTION_BY_ID[request.id]
    if not descriptor then return nil, usage("unknown semantic action", request.id) end
    local normalized, facts_error = normalize_facts(facts, request)
    if not normalized then return nil, facts_error end
    if request.machine == true then
        if not MACHINE_SUPPORTED[request.id]
            or (request.id == "self-test" and (request.through_stage or 1) ~= 1)
        then
            return nil, usage(
                "--machine is unsupported for this action",
                request.id
            )
        end
        return "machine-json-or-jsonl"
    end
    if request.id == "help" or request.id == "version" then return "human-text" end
    local interactive = normalized.stdin_is_tty and normalized.stdout_is_tty
    if request.id == "self-test" then
        if interactive then return "human-interactive" end
        if (request.through_stage or 1) == 1 then return "human-text" end
        if request.online_consent == true then return "human-text" end
        return nil, failure(
            "OnlineConsentRequired",
            "non-TTY online self-test requires explicit current-invocation consent"
        )
    end
    if not interactive then
        return nil, failure(
            "TtyRequired",
            "this action requires both stdin and stdout to be interactive terminals"
        )
    end
    return "human-interactive"
end

local function argv_alias(token, platform)
    local descriptor = ARGV_LONG[token] or ARGV_SHORT[token]
    if descriptor then return descriptor end
    if platform == "windows" then return ARGV_SLASH[token] end
    return nil
end

local function starts_option(token, platform)
    if token:sub(1, 1) == "-" then return true end
    if platform == "windows" and ARGV_SLASH[token] then return true end
    return false
end

local function parse_argv(platform, values, facts)
    local tokens, tokens_error = dense_string_array(values)
    if not tokens then return nil, tokens_error end
    local descriptor
    local positionals = {}
    local request = {}
    local option_mode = true
    local machine_seen = false
    local named_seen = {}
    local index = 1

    while index <= #tokens do
        local token = tokens[index]
        if option_mode and token == REGISTRY.parser.end_of_options then
            option_mode = false
            index = index + 1
        elseif option_mode and token == "--machine" then
            if machine_seen then return nil, usage("--machine may be supplied only once") end
            machine_seen = true
            request.machine = true
            index = index + 1
        else
            local projected = option_mode and argv_alias(token, platform) or nil
            if projected then
                if descriptor then
                    return nil, usage("more than one primary action was supplied")
                end
                descriptor = projected
                request.id = descriptor.id
                index = index + 1
            elseif descriptor and option_mode then
                local named = named_argument_map(descriptor)[token]
                if named then
                    if named_seen[named.name] and not named.repeatable then
                        return nil, usage(
                            named.spelling .. " may be supplied only once",
                            descriptor.id,
                            named.name
                        )
                    end
                    named_seen[named.name] = true
                    if named.type == "bool" then
                        request[named.name] = true
                        index = index + 1
                    else
                        local raw = tokens[index + 1]
                        if raw == nil or raw == REGISTRY.parser.end_of_options
                            or starts_option(raw, platform)
                        then
                            return nil, usage(
                                "missing value for " .. named.spelling,
                                descriptor.id,
                                named.name
                            )
                        end
                        local scalar_specification = {
                            name = named.name,
                            type = named.type:gsub("%-list$", ""),
                        }
                        local admitted, validation_error = validate_scalar(
                            scalar_specification,
                            raw
                        )
                        if admitted == nil then
                            return nil, usage(
                                "invalid " .. named.name .. ": " .. validation_error,
                                descriptor.id,
                                named.name
                            )
                        end
                        if named.repeatable then
                            request[named.name] = request[named.name] or {}
                            request[named.name][#request[named.name] + 1] = admitted
                        else
                            request[named.name] = admitted
                        end
                        index = index + 2
                    end
                elseif starts_option(token, platform) then
                    return nil, usage("unknown option " .. token, descriptor.id)
                else
                    positionals[#positionals + 1] = token
                    index = index + 1
                end
            elseif option_mode and starts_option(token, platform) then
                return nil, usage("unknown option " .. token)
            else
                if not descriptor then
                    descriptor = ACTION_BY_ID["run-chat"]
                    request.id = descriptor.id
                end
                positionals[#positionals + 1] = token
                index = index + 1
            end
        end
    end

    if not descriptor then
        descriptor = ACTION_BY_ID["run-chat"]
        request.id = descriptor.id
    end
    local assigned, assignment_error = assign_positionals(
        descriptor,
        request,
        positionals
    )
    if not assigned then return nil, assignment_error end
    if facts ~= nil then
        local mode, mode_error = fd_mode(request, facts)
        if not mode then return nil, mode_error end
    end
    return request
end

local function skip_space(source, index)
    while index <= #source do
        local byte = source:byte(index)
        if byte ~= 0x20 and byte ~= 0x09 then break end
        index = index + 1
    end
    return index
end

local function read_token(source, index)
    index = skip_space(source, index)
    if index > #source then return nil, index end
    local quote = source:sub(index, index)
    if quote ~= "\"" and quote ~= "'" then
        local finish = index
        while finish <= #source do
            local byte = source:byte(finish)
            if byte == 0x20 or byte == 0x09 then break end
            finish = finish + 1
        end
        return source:sub(index, finish - 1), finish
    end
    local parts = {}
    index = index + 1
    while index <= #source do
        local character = source:sub(index, index)
        if character == quote then return table.concat(parts), index + 1 end
        if character == "\\" then
            local following = source:sub(index + 1, index + 1)
            if following == quote or following == "\\" then
                parts[#parts + 1] = following
                index = index + 2
            else
                parts[#parts + 1] = character
                index = index + 1
            end
        else
            parts[#parts + 1] = character
            index = index + 1
        end
    end
    return nil, index, "unterminated quoted value"
end

local function trim_line(value)
    return value:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
end

local function line_matches(source, literal)
    if source:sub(1, #literal) ~= literal then return false end
    if #source == #literal then return true end
    local byte = source:byte(#literal + 1)
    return byte == 0x20 or byte == 0x09
end

local function remove_named_boolean(rest, specification)
    local spelling = specification.spelling
    local cursor = 1
    while true do
        local start_index = skip_space(rest, cursor)
        if start_index > #rest then break end
        local _, following, token_error = read_token(rest, start_index)
        if token_error then return rest, false end
        if rest:sub(start_index, following - 1) == spelling
            and skip_space(rest, following) > #rest
        then
            return trim_line(rest:sub(1, start_index - 1)), true
        end
        if rest:sub(start_index, following - 1) == spelling then
            return rest, false, true
        end
        cursor = following
    end
    return rest, false
end

local function parse_line_values(indexed, rest)
    local descriptor = indexed.action
    local request = { id = descriptor.id }
    for _, specification in ipairs(descriptor.args) do
        if specification.spelling then
            local found, misplaced
            rest, found, misplaced = remove_named_boolean(rest, specification)
            if misplaced then
                return nil, usage(
                    specification.spelling .. " must be the final command token",
                    descriptor.id,
                    specification.name
                )
            end
            if found then request[specification.name] = true end
        end
    end
    rest = trim_line(rest)
    local specifications = positional_arguments(descriptor)
    local values = {}
    local cursor = 1
    for argument_index, specification in ipairs(specifications) do
        cursor = skip_space(rest, cursor)
        if cursor > #rest then break end
        if argument_index == #specifications then
            local remainder = trim_line(rest:sub(cursor))
            if specification.type == "bounded-utf8-text" then
                values[#values + 1] = remainder
            else
                local token, following, token_error = read_token(rest, cursor)
                if token_error then
                    return nil, usage(token_error, descriptor.id, specification.name)
                end
                if skip_space(rest, following) > #rest then
                    values[#values + 1] = token
                else
                    values[#values + 1] = remainder
                end
            end
            cursor = #rest + 1
        else
            local token, following, token_error = read_token(rest, cursor)
            if token_error then
                return nil, usage(token_error, descriptor.id, specification.name)
            end
            values[#values + 1] = token
            cursor = following
        end
    end
    if skip_space(rest, cursor) <= #rest then
        return nil, usage("too many line arguments", descriptor.id)
    end
    return assign_positionals(
        descriptor,
        request,
        values,
        indexed.projection.required_args
    )
end

local function parse_projected_line(kind, source, facts)
    if not valid_utf8_string(source) or source:find("[\r\n]", 1) then
        return nil, usage("command line must be one UTF-8 line")
    end
    local normalized = trim_line(source)
    if normalized == "" then return nil, usage("command line is empty") end
    local projections = LINE_PROJECTIONS[kind]
    for _, indexed in ipairs(projections) do
        if line_matches(normalized, indexed.literal) then
            local rest = normalized:sub(#indexed.literal + 1)
            local request, parse_error = parse_line_values(indexed, rest)
            if not request then return nil, parse_error end
            if facts ~= nil then
                local synthetic = {
                    id = request.id,
                    machine = false,
                }
                local normalized_facts, facts_error = normalize_facts(facts, synthetic)
                if not normalized_facts then return nil, facts_error end
                local is_tty = normalized_facts.stdin_is_tty
                    and normalized_facts.stdout_is_tty
                if kind == "chat-line" and not is_tty then
                    return nil, failure(
                        "TtyRequired",
                        "chat commands require both stdin and stdout terminals"
                    )
                end
                if kind == "context-repl-line" and not is_tty
                    and indexed.action.confirm ~= "none"
                    and request.yes ~= true
                then
                    return nil, failure(
                        "ApprovalRequired",
                        "non-TTY confirmed Context actions require explicit --yes"
                    )
                end
            end
            return request
        end
    end
    return nil, usage("unknown command line")
end

local function closest_topic(topic, topics)
    local function distance(left, right)
        local previous = {}
        for column = 0, #right do previous[column] = column end
        for row = 1, #left do
            local current = { [0] = row }
            for column = 1, #right do
                local cost = left:byte(row) == right:byte(column) and 0 or 1
                current[column] = math.min(
                    current[column - 1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + cost
                )
            end
            previous = current
        end
        return previous[#right]
    end
    local best, best_distance
    for _, candidate in ipairs(topics) do
        local candidate_distance = distance(topic, candidate)
        if not best_distance or candidate_distance < best_distance
            or (candidate_distance == best_distance and candidate < best)
        then
            best, best_distance = candidate, candidate_distance
        end
    end
    return best
end

local function argv_projection(descriptor)
    for _, projection in ipairs(descriptor.projections) do
        if projection.kind == "argv" then return projection end
    end
    return nil
end

local function action_usage(descriptor)
    local values = {}
    for _, projection in ipairs(descriptor.projections) do
        if projection.kind == "argv" then
            values[#values + 1] = descriptor.overview_usage
        else
            values[#values + 1] = projection.command
        end
    end
    return values
end

local function aliases_text(descriptor)
    local projection = argv_projection(descriptor)
    if not projection or projection.long == false then return "default positional action" end
    return table.concat({
        projection.long,
        projection.short,
        projection.slash .. " (Windows only)",
    }, ", ")
end

local function render_overview(product_name)
    local lines = {
        product_name .. ": Yet Another Coding Agent.",
        "",
        "Usage:",
    }
    for _, descriptor in ipairs(ACTIONS) do
        if argv_projection(descriptor) then
            lines[#lines + 1] = "  " .. descriptor.overview_usage
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Canonical actions:"
    for _, descriptor in ipairs(ACTIONS) do
        local projection = argv_projection(descriptor)
        if projection and projection.long ~= false then
            lines[#lines + 1] = string.format(
                "  %-18s %-6s %-6s %s",
                projection.long,
                projection.short,
                projection.slash,
                descriptor.summary
            ):gsub(" +$", "")
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Self-test options:"
    local self_test = ACTION_BY_ID["self-test"]
    for _, specification in ipairs(self_test.args) do
        local suffix = ""
        if specification.type ~= "bool" then
            suffix = specification.type == "enum:1|2|3" and " 1|2|3" or " <value>"
        end
        if specification.repeatable then suffix = suffix .. " (repeatable)" end
        lines[#lines + 1] = "  " .. specification.spelling .. suffix
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Global modifier:"
    lines[#lines + 1] = "  --machine  Emit versioned JSON/JSONL for help, version, or offline Stage 1."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Rules:"
    lines[#lines + 1] = "  -- ends option parsing; use it before a directory beginning with '-'."
    lines[#lines + 1] = "  / aliases are recognized only on Windows; Linux / paths stay positional."
    lines[#lines + 1] = "  Interactive actions require both stdin and stdout to be terminals."
    lines[#lines + 1] = "  Short Context name selects the first usable match; use hash for precision."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Topics: chat, context, input, actions, or any semantic action ID."
    return table.concat(lines, "\n") .. "\n"
end

local function render_surface(kind, title)
    local lines = { title, "" }
    for _, descriptor in ipairs(ACTIONS) do
        for _, projection in ipairs(descriptor.projections) do
            if projection.kind == kind then
                lines[#lines + 1] = string.format(
                    "  %-48s %s",
                    projection.command,
                    descriptor.summary
                ):gsub(" +$", "")
            end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

local function render_input_help()
    local rows = {}
    for _, descriptor in ipairs(ACTIONS) do
        for _, projection in ipairs(descriptor.projections) do
            if projection.kind == "chat-line" and projection.key ~= false then
                rows[#rows + 1] = {
                    key = projection.key,
                    command = projection.command,
                    id = descriptor.id,
                }
            end
        end
    end
    table.sort(rows, function(left, right) return left.key < right.key end)
    local lines = { "Input bindings and text fallbacks", "" }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = string.format(
            "  %-18s %-24s %s",
            row.key,
            row.command,
            row.id
        ):gsub(" +$", "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Unavailable enhanced keys never remove their text fallback."
    return table.concat(lines, "\n") .. "\n"
end

local function render_action_help(descriptor)
    local lines = {
        "Action: " .. descriptor.id,
        "Summary: " .. descriptor.summary,
        "Surface: " .. descriptor.surface,
        "TTY: " .. descriptor.tty,
        "Confirmation: " .. descriptor.confirm,
        "Usage:",
    }
    for _, value in ipairs(action_usage(descriptor)) do lines[#lines + 1] = "  " .. value end
    local projection = argv_projection(descriptor)
    if projection then lines[#lines + 1] = "Aliases: " .. aliases_text(descriptor) end
    if #descriptor.args > 0 then
        lines[#lines + 1] = "Arguments:"
        for _, specification in ipairs(descriptor.args) do
            local required = specification.required and "required" or "optional"
            local spelling = specification.spelling and (", " .. specification.spelling) or ""
            local default = specification.default ~= nil
                and (", default=" .. tostring(specification.default)) or ""
            lines[#lines + 1] = string.format(
                "  %s: %s (%s%s%s)",
                specification.name,
                specification.type,
                required,
                spelling,
                default
            )
        end
    end
    lines[#lines + 1] = "Results: " .. table.concat(descriptor.results, ", ")
    if MACHINE_SUPPORTED[descriptor.id] then
        local constraint = descriptor.id == "self-test" and " (offline Stage 1 only)" or ""
        lines[#lines + 1] = "Machine: supported" .. constraint
    else
        lines[#lines + 1] = "Machine: unsupported"
    end
    return table.concat(lines, "\n") .. "\n"
end

local function render_help(product_name, topic)
    if topic == nil or topic == "" or topic == "top" then
        return render_overview(product_name)
    end
    if type(topic) ~= "string" or not topic:match("^[a-z0-9][a-z0-9%-]*$") then
        return nil, usage("help topic must be one ASCII topic ID")
    end
    if topic == "chat" then return render_surface("chat-line", "Chat commands") end
    if topic == "context" then
        return render_surface("context-repl-line", "Context REPL commands")
    end
    if topic == "input" then return render_input_help() end
    if topic == "actions" then
        local lines = { "Semantic actions", "" }
        for _, descriptor in ipairs(ACTIONS) do
            lines[#lines + 1] = string.format(
                "  %-42s %-12s %s",
                descriptor.id,
                descriptor.surface,
                descriptor.summary
            ):gsub(" +$", "")
        end
        return table.concat(lines, "\n") .. "\n"
    end
    local descriptor = ACTION_BY_ID[topic]
    if descriptor then return render_action_help(descriptor) end
    local topics = { "actions", "chat", "context", "input", "top" }
    for _, candidate in ipairs(ACTIONS) do topics[#topics + 1] = candidate.id end
    table.sort(topics)
    local suggestion = closest_topic(topic, topics)
    return nil, usage("unknown help topic", nil, nil), suggestion
end

local function stable_machine_token(value, field)
    if type(value) ~= "string" or not value:match("^[a-z][a-z0-9%-]*$") then
        return nil, failure(
            "InvalidMachineValue",
            field .. " must be a stable lowercase ASCII token"
        )
    end
    return value
end

local function stable_schema_token(value)
    return type(value) == "string"
        and value:match("^[a-z][a-z0-9._%-]*$") ~= nil
end

local function table_shape(value)
    local count, maximum, string_keys = 0, 0, false
    for key in pairs(value) do
        count = count + 1
        if math.type(key) == "integer" and key >= 1 then
            if key > maximum then maximum = key end
        elseif type(key) == "string" then
            string_keys = true
        else
            return nil
        end
    end
    if count == 0 then return "object", 0 end
    if not string_keys and maximum == count then return "array", count end
    if maximum == 0 then return "object", count end
    return nil
end

local function machine_json_value(value, seen, depth, maximum_depth)
    local kind = json.kind(value)
    if kind and kind ~= "array" and kind ~= "object" then return value end
    local value_type = type(value)
    if value_type == "string" then
        if not text.validate_utf8(value) then
            return nil, failure("InvalidMachineValue", "machine strings must be valid UTF-8")
        end
        return value
    end
    if value_type == "boolean" then return value end
    if value_type == "number" then
        local lexeme
        if math.type(value) == "integer" then
            lexeme = tostring(value)
        else
            lexeme = string.format("%.17g", value)
        end
        local number, number_error = json.number(lexeme)
        if not number then
            return nil, failure("InvalidMachineValue", number_error.message)
        end
        return number
    end
    if value_type ~= "table" then
        return nil, failure("InvalidMachineValue", "machine values must be JSON-compatible")
    end
    if depth > maximum_depth then
        return nil, failure("InvalidMachineValue", "machine value exceeds JSON depth")
    end
    if seen[value] then
        return nil, failure("InvalidMachineValue", "machine value contains a cycle")
    end
    seen[value] = true
    local detected_shape, count = table_shape(value)
    local shape = kind or detected_shape
    if shape == "array" then
        local values = {}
        for index = 1, count do
            local converted, conversion_error = machine_json_value(
                value[index], seen, depth + 1, maximum_depth
            )
            if converted == nil then seen[value] = nil return nil, conversion_error end
            values[index] = converted
        end
        seen[value] = nil
        return json.array(values)
    end
    if shape == "object" then
        local values = {}
        for key, item in pairs(value) do
            if not key:match("^[a-z][a-z0-9_]*$") then
                seen[value] = nil
                return nil, failure(
                    "InvalidMachineValue",
                    "machine field names must be lowercase ASCII snake_case"
                )
            end
            local converted, conversion_error = machine_json_value(
                item, seen, depth + 1, maximum_depth
            )
            if converted == nil then seen[value] = nil return nil, conversion_error end
            values[key] = converted
        end
        seen[value] = nil
        return json.object(values)
    end
    seen[value] = nil
    return nil, failure("InvalidMachineValue", "machine table shape is ambiguous")
end

local function add_machine_fields(target, fields, reserved)
    if fields == nil then return true end
    if type(fields) ~= "table" then
        return nil, failure("InvalidMachineValue", "machine fields must be a table")
    end
    for key, value in pairs(fields) do
        if type(key) ~= "string" or reserved[key] then
            return nil, failure("InvalidMachineValue", "machine fields use a reserved key")
        end
        target[key] = value
    end
    return true
end

local function encode_machine(codec, maximum_depth, value)
    if not codec then
        return nil, failure("MachineCodecUnavailable", "a bounded JSON codec is required")
    end
    local converted, conversion_error = machine_json_value(
        value,
        {},
        1,
        maximum_depth
    )
    if not converted then return nil, conversion_error end
    local encoded, encoding_error = codec.write(converted)
    if not encoded then return nil, encoding_error end
    return encoded
end

local function completion(surface, prefix, platform)
    prefix = prefix or ""
    if type(prefix) ~= "string" or not valid_utf8_string(prefix) then
        return nil, usage("completion prefix must be UTF-8 text")
    end
    local candidates = {}
    if surface == "top" then
        candidates[#candidates + 1] = "--machine"
        for _, descriptor in ipairs(ACTIONS) do
            local projection = argv_projection(descriptor)
            if projection and projection.long then
                candidates[#candidates + 1] = projection.long
                candidates[#candidates + 1] = projection.short
                if platform == "windows" then candidates[#candidates + 1] = projection.slash end
            end
        end
    elseif surface == "chat" or surface == "context" then
        local kind = surface == "chat" and "chat-line" or "context-repl-line"
        for _, indexed in ipairs(LINE_PROJECTIONS[kind]) do
            candidates[#candidates + 1] = indexed.literal
        end
    else
        return nil, usage("completion surface must be top, chat, or context")
    end
    local seen, result = {}, {}
    table.sort(candidates)
    for _, candidate in ipairs(candidates) do
        if not seen[candidate] and candidate:sub(1, #prefix) == prefix then
            seen[candidate] = true
            result[#result + 1] = candidate
        end
    end
    return result
end

---Returns a detached copy of the complete semantic action registry.
-- @return table registry Mutable copy safe for inspection by adapters/tests.
function M.registry()
    return deep_copy(REGISTRY)
end

---Creates a CLI projection service for one release-platform parser.
-- Parsing and human help do not require the optional JSON codec. Machine
-- rendering fails closed until a bounded codec is injected.
-- @param options table Platform, product identity, schema, and optional codec.
-- @return table|nil service Immutable CLI adapter.
-- @return table|nil err Structured construction failure.
function M.new(options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, failure("InvalidCliOptions", "CLI options must be a table")
    end
    local allowed = {
        platform = true,
        product_name = true,
        machine_schema_version = true,
        json_codec = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidCliOptions", "CLI options contain an unknown field")
        end
    end
    local platform = options.platform
    if platform ~= "linux" and platform ~= "windows" then
        return nil, failure("InvalidCliOptions", "platform must be linux or windows")
    end
    local product_name = options.product_name or "yaca"
    if type(product_name) ~= "string" or not product_name:match("^[A-Za-z0-9._-]+$") then
        return nil, failure("InvalidCliOptions", "product_name must be a nonempty ASCII token")
    end
    local schema_version = options.machine_schema_version
        or REGISTRY.machine_output.schema_version
    if not stable_schema_token(schema_version) then
        return nil, failure(
            "InvalidCliOptions",
            "machine_schema_version must be a stable lowercase ASCII version token"
        )
    end
    local codec = options.json_codec
    if codec ~= nil and (type(codec) ~= "table" or type(codec.write) ~= "function") then
        return nil, failure("InvalidCliOptions", "json_codec must provide write")
    end
    if codec ~= nil and (type(codec.limits) ~= "table"
        or math.type(codec.limits.maximum_depth) ~= "integer"
        or codec.limits.maximum_depth < 1)
    then
        return nil, failure(
            "InvalidCliOptions",
            "json_codec must expose its injected maximum_depth"
        )
    end
    local maximum_depth = codec and codec.limits.maximum_depth or 0
    local service = {}

    ---Returns a detached registry copy.
    function service.registry()
        return M.registry()
    end

    ---Returns one detached semantic action descriptor.
    function service.action(id)
        local descriptor = ACTION_BY_ID[id]
        if not descriptor then return nil, usage("unknown semantic action", id) end
        return deep_copy(descriptor)
    end

    ---Parses argv into one normalized semantic request and applies fd gates.
    -- @param values table Dense argv strings excluding the executable name.
    -- @param facts table|nil Independent stdin/stdout/stderr TTY facts.
    -- @return table|nil request Normalized semantic action request.
    -- @return table|nil err Structured grammar/admission failure.
    function service.parse_argv(values, facts)
        return parse_argv(platform, values, facts)
    end

    ---Parses one chat line into the same semantic action vocabulary.
    function service.parse_chat(source, facts)
        if valid_utf8_string(source) then
            local normalized = trim_line(source)
            if normalized ~= "" and normalized:sub(1, 1) ~= "." then
                local request = { id = "queue-add", message = source }
                if facts ~= nil then
                    local normalized_facts, facts_error = normalize_facts(
                        facts,
                        { id = request.id, machine = false }
                    )
                    if not normalized_facts then return nil, facts_error end
                    if not normalized_facts.stdin_is_tty
                        or not normalized_facts.stdout_is_tty
                    then
                        return nil, failure(
                            "TtyRequired",
                            "chat input requires both stdin and stdout terminals"
                        )
                    end
                end
                return request
            end
        end
        return parse_projected_line("chat-line", source, facts)
    end

    ---Parses one Context REPL command line into a semantic request.
    function service.parse_context_repl(source, facts)
        return parse_projected_line("context-repl-line", source, facts)
    end

    ---Returns the renderer mode or a typed fd/action admission failure.
    function service.fd_mode(request, facts)
        return fd_mode(request, facts)
    end

    ---Renders overview, surface, input, or action help from the registry.
    function service.render_help(topic)
        local rendered, render_error, suggestion = render_help(product_name, topic)
        if not rendered and suggestion then render_error.suggestion = suggestion end
        return rendered, render_error
    end

    ---Returns deterministic registry-derived completion candidates.
    function service.complete(surface, prefix)
        return completion(surface, prefix, platform)
    end

    ---Renders one complete versioned RFC 8259 machine result.
    function service.machine_result(kind, outcome, fields)
        local admitted_kind, kind_error = stable_machine_token(kind, "kind")
        if not admitted_kind then return nil, kind_error end
        local admitted_outcome, outcome_error = stable_machine_token(outcome, "outcome")
        if not admitted_outcome then return nil, outcome_error end
        local value = {
            schema_version = schema_version,
            kind = admitted_kind,
            outcome = admitted_outcome,
        }
        local added, fields_error = add_machine_fields(value, fields, {
            schema_version = true, kind = true, outcome = true,
        })
        if not added then return nil, fields_error end
        local encoded, encoding_error = encode_machine(codec, maximum_depth, value)
        if not encoded then return nil, encoding_error end
        return encoded .. "\n"
    end

    ---Renders a contiguous JSONL stream; the last record must carry outcome.
    function service.machine_stream(kind, records)
        local admitted_kind, kind_error = stable_machine_token(kind, "kind")
        if not admitted_kind then return nil, kind_error end
        if type(records) ~= "table" then
            return nil, failure("InvalidMachineStream", "machine stream requires records")
        end
        local count, maximum = 0, 0
        for key in pairs(records) do
            if math.type(key) ~= "integer" or key < 1 then
                return nil, failure("InvalidMachineStream", "machine records must be dense")
            end
            count = count + 1
            if key > maximum then maximum = key end
        end
        if count == 0 then
            return nil, failure("InvalidMachineStream", "machine stream requires records")
        end
        if count ~= maximum then
            return nil, failure("InvalidMachineStream", "machine records must be dense")
        end
        local lines = {}
        for index = 1, count do
            local fields = records[index]
            if type(fields) ~= "table" then
                return nil, failure("InvalidMachineStream", "machine record must be a table")
            end
            local final = index == count
            if final and fields.outcome == nil then
                return nil, failure("InvalidMachineStream", "final record requires outcome")
            end
            if not final and fields.outcome ~= nil then
                return nil, failure(
                    "InvalidMachineStream",
                    "only the final record may contain outcome"
                )
            end
            if fields.outcome ~= nil then
                local outcome, outcome_error = stable_machine_token(fields.outcome, "outcome")
                if not outcome then return nil, outcome_error end
            end
            local value = {
                schema_version = schema_version,
                kind = admitted_kind,
                sequence = index,
                final = final,
            }
            local added, fields_error = add_machine_fields(value, fields, {
                schema_version = true, kind = true, sequence = true, final = true,
            })
            if not added then return nil, fields_error end
            local encoded, encoding_error = encode_machine(codec, maximum_depth, value)
            if not encoded then return nil, encoding_error end
            lines[#lines + 1] = encoded
        end
        return table.concat(lines, "\n") .. "\n"
    end

    ---Writes an already-rendered payload and converts broken stdout to failure.
    function service.emit(writer, bytes)
        if type(bytes) ~= "string" then
            return nil, failure("InvalidOutput", "output bytes must be a string")
        end
        local called, result, writer_error
        if type(writer) == "function" then
            called, result, writer_error = pcall(writer, bytes)
        elseif type(writer) == "table" and type(writer.write) == "function" then
            called, result, writer_error = pcall(writer.write, writer, bytes)
        else
            return nil, failure("InvalidOutput", "stdout writer must provide write")
        end
        if not called or result == nil or result == false then
            return nil, failure("BrokenStdout", "stdout closed before output completed", {
                close_required = true,
                reason = called and tostring(writer_error or "write failed")
                    or "writer raised an exception",
            })
        end
        return true
    end

    ---Maps a typed error/result to the stable registry exit class code.
    function service.exit_code(value)
        if value == nil then return REGISTRY.exit_classes.general_error end
        if type(value) == "string" then
            local class = REGISTRY.error_exit_classes[value]
                or REGISTRY.outcome_exit_classes[value]
            return REGISTRY.exit_classes[class or "general_error"]
        end
        if type(value) ~= "table" then return REGISTRY.exit_classes.general_error end
        if value.exit_class ~= nil then
            local code = REGISTRY.exit_classes[value.exit_class]
            if code ~= nil then return code end
            return REGISTRY.exit_classes.general_error
        end
        if type(value.code) == "string" then
            local class = REGISTRY.error_exit_classes[value.code] or "general_error"
            return REGISTRY.exit_classes[class]
        end
        if type(value.outcome) == "string" then
            local class = REGISTRY.outcome_exit_classes[value.outcome]
            return REGISTRY.exit_classes[class or "general_error"]
        end
        return REGISTRY.exit_classes.general_error
    end

    return readonly(service, "CLI service")
end

return M
