--[[
Author: WaterRun
Date: 2026-09-23
File: permission.lua
Description: Evaluates fixed tool capabilities and one-action approval bindings.
]]

local text = require("text")

local M = {}

local CAPABILITIES = { "Read", "Write", "Delete", "Shell", "OutsideWorkspace" }
local DECISION_RANK = { allow = 0, confirm = 1, deny = 2 }
local RANK_DECISION = { [0] = "allow", [1] = "confirm", [2] = "deny" }

local TOOLS = {
    list = { caps = { "Read" }, target_kind = "direct-path", high_risk = false },
    read = { caps = { "Read" }, target_kind = "direct-path", high_risk = false },
    search = { caps = { "Read" }, target_kind = "direct-path", high_risk = false },
    write = { caps = { "Write" }, target_kind = "direct-path", high_risk = true },
    patch = { caps = { "Write" }, target_kind = "direct-path", high_risk = true },
    rename = { caps = { "Write", "Delete" }, target_kind = "direct-path", high_risk = true },
    delete = { caps = { "Delete" }, target_kind = "direct-path", high_risk = true },
    exec = { caps = { "Shell" }, target_kind = "opaque-command", high_risk = true },
    lua = { caps = { "Shell" }, target_kind = "opaque-code", high_risk = true },
}

local TOOL_ORDER = { "list", "read", "search", "write", "patch", "rename", "delete", "exec", "lua" }
local PROCESS_TOOLS = { exec = true, lua = true }

local OPTION_NAMES = {
    "maximum_name_bytes",
    "maximum_generation_bytes",
    "maximum_arguments_bytes",
    "maximum_target_bytes",
    "maximum_identity_bytes",
    "maximum_prompt_bytes",
}

local SNAPSHOT_FIELDS = {
    "schema_version",
    "registry_digest",
    "canonical_arguments",
    "canonical_target",
    "expected_raw_digest",
    "cwd",
    "workspace_root_identity",
    "operation_id",
    "tool_call_id",
}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param detail any|nil Optional underlying cause or contextual diagnostic data; retained as supplied.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
    return result
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __len function Reports the backing table sequence length.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        -- Forward sequence-length queries to the backing table.
        --@param none The proxy operand supplied by Lua is ignored.
        --@return integer Length of the backing sequence under the Lua length operator.
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Count a dense one-based array while rejecting holes and extra key kinds.
--@param values any Candidate table; every key must belong to the sequence 1 through count.
--@return integer|nil Sequence length, including zero for an empty table; nil for an invalid shape.
local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do if values[index] == nil then return nil end end
    return count
end

-- Require precisely the named string fields on a record, with none missing.
--@param value any Candidate record to inspect without mutation.
--@param names table Required field-name sequence.
--@return boolean exact Whether every and only the required fields is present.
local function exact_keys(value, names)
    if type(value) ~= "table" then return false end
    local allowed = {}
    for _, name in ipairs(names) do allowed[name] = true end
    for key in pairs(value) do if type(key) ~= "string" or not allowed[key] then return false end end
    for _, name in ipairs(names) do if value[name] == nil then return false end end
    return true
end

-- Check bounded strict UTF-8 text used in policy and approval identities.
--@param value any Candidate text.
--@param maximum integer Inclusive byte limit.
--@param allow_empty boolean Whether an empty string is admitted.
--@return boolean valid Whether the candidate is admitted.
local function valid_text(value, maximum, allow_empty)
    if type(value) ~= "string" or #value > maximum or (not allow_empty and value == "") then return false end
    local valid = text.validate_utf8(value)
    return valid == true
end

-- Admit a bounded non-empty token without NUL or line breaks.
--@param value any Candidate identity token.
--@param maximum integer Inclusive byte limit.
--@return boolean valid Whether the token can be bound in an approval.
local function valid_token(value, maximum)
    return valid_text(value, maximum, false) and not value:find("[%z\r\n]")
end

-- Snapshot the safety callbacks needed to freeze and bind permission records.
--@param ports table Candidate constructor ports containing only safety.
--@return table|nil safety Independent table of required safety callback references.
--@return table|nil err Structured port-shape or missing-callback failure.
local function validate_ports(ports)
    if type(ports) ~= "table" or type(ports.safety) ~= "table" then
        return nil, failure("InvalidPermissionPorts", "a safety service is required")
    end
    for key in pairs(ports) do
        if key ~= "safety" then
            return nil, failure("InvalidPermissionPorts", "Permission ports contain an unknown field")
        end
    end
    local result = {}
    for _, method in ipairs({ "freeze", "digest", "binding_digest" }) do
        if type(ports.safety[method]) ~= "function" then
            return nil, failure("InvalidPermissionPorts", "safety service omits " .. method)
        end
        result[method] = ports.safety[method]
    end
    return result
end

-- Validate and copy all required permission byte limits.
--@param options table Candidate limit record; unknown fields are rejected.
--@return table|nil limits Independent validated limit table.
--@return table|nil err Structured option-shape or inconsistent-limit failure.
local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidPermissionOptions", "Permission hard limits are required")
    end
    local allowed, result = {}, {}
    for _, name in ipairs(OPTION_NAMES) do allowed[name] = true end
    for key in pairs(options) do
        if not allowed[key] then
            return nil, failure("InvalidPermissionOptions", "Permission options contain an unknown field")
        end
    end
    for _, name in ipairs(OPTION_NAMES) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidPermissionOptions", "Permission limits must be positive integers")
        end
        result[name] = options[name]
    end
    if result.maximum_name_bytes > result.maximum_identity_bytes
        or result.maximum_generation_bytes > result.maximum_identity_bytes
    then
        return nil, failure("InvalidPermissionOptions", "Permission sub-limits are inconsistent")
    end
    return result
end

-- Ask the safety port for a lowercase SHA-256 binding digest.
--@param safety table Validated safety callbacks.
--@param domain string Domain-separation label for this binding.
--@param fields table Ordered named values bound by the digest.
--@return string|nil digest Exactly 64 lowercase hexadecimal characters.
--@return table|nil err Structured native or digest-format failure.
local function binding_digest(safety, domain, fields)
    local called, digest, digest_error = pcall(safety.binding_digest, domain, fields)
    if not called or type(digest) ~= "string" or #digest ~= 64
        or not digest:match("^[0-9a-f]+$")
    then
        return nil, digest_error or failure("PermissionDigest", "Permission binding digest failed")
    end
    return digest
end

-- Freeze a public record through the safety port while containing exceptions.
--@param safety table Validated safety callbacks.
--@param value table Record to freeze; ownership of its nested values passes to safety.freeze.
--@param label string Diagnostic label for attempted mutation.
--@return table|nil frozen Public immutable record.
--@return table|nil err Structured freeze failure.
--@ownership The returned record is owned by the safety port; callers retain no mutation authority.
local function freeze(safety, value, label)
    local called, frozen, freeze_error = pcall(safety.freeze, value, label)
    if not called or frozen == nil then
        return nil, freeze_error or failure("PermissionFreeze", "Permission snapshot freeze failed")
    end
    return frozen
end

-- Serialize capability decisions in fixed order for a stable digest.
--@param matrix table Capability-to-decision map, read without mutation.
--@return table fields Ordered named decision records.
local function matrix_fields(matrix)
    local fields = {}
    for index, capability in ipairs(CAPABILITIES) do
        fields[index] = { name = capability, value = matrix[capability] }
    end
    return fields
end

-- Copy the contiguous array prefix while retaining element references.
--@param values table Sequence copied with ipairs.
--@return table New sequence containing the original element values through the first hole.
--@ownership Copies the outer table only; nested objects retain their original owners.
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

-- Copy all map entries without duplicating nested policy values.
--@param values table Source map enumerated with pairs.
--@return table New outer map containing the same keys and values.
--@ownership Nested objects remain shared with the source map.
local function copy_map(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end

---Creates deterministic Permission and one-action approval services.
--@param ports table Constructor ports containing the safety service.
--@param options table Required byte limits for profiles, decisions, and approvals.
--@return table|nil service Read-only permission service with private authority registries.
--@return table|nil err Structured port or limit validation failure.
function M.new(ports, options)
    local safety, ports_error = validate_ports(ports)
    if not safety then return nil, ports_error end
    local limits, options_error = validate_options(options)
    if not limits then return nil, options_error end
    --@metatable profiles Associates public permission profiles with the validated policy owned by this service.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local profiles = setmetatable({}, { __mode = "k" })
    --@metatable decisions Associates public decisions with their private evaluated policy and capability facts.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local decisions = setmetatable({}, { __mode = "k" })
    --@metatable snapshots Associates approval snapshots with the private operation facts bound to confirmation.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local snapshots = setmetatable({}, { __mode = "k" })
    --@metatable approvals Associates approval tokens with their private one-action authorization state.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local approvals = setmetatable({}, { __mode = "k" })
    local service = {}

    -- Freeze a validated effective permission profile and register its private facts.
    --@param self table Permission service; private registries remain captured here.
    --@param spec table Name, generation, matrix, description, and prompt fields.
    --@return table|nil profile Immutable current-process profile.
    --@return table|nil err Structured shape, capability, digest, or freeze failure.
    function service:profile(spec)
        if not exact_keys(spec, {
            "name", "config_generation", "matrix", "description", "system_prompt",
        }) then
            return nil, failure("InvalidPermissionProfile", "Permission profile fields are invalid")
        end
        if not valid_token(spec.name, limits.maximum_name_bytes)
            or not valid_token(spec.config_generation, limits.maximum_generation_bytes)
            or not valid_text(spec.description, limits.maximum_prompt_bytes, true)
            or not valid_text(spec.system_prompt, limits.maximum_prompt_bytes, true)
            or not exact_keys(spec.matrix, CAPABILITIES)
        then
            return nil, failure("InvalidPermissionProfile", "Permission profile identity or matrix is invalid")
        end
        local matrix = {}
        for _, capability in ipairs(CAPABILITIES) do
            local decision = spec.matrix[capability]
            if DECISION_RANK[decision] == nil then
                return nil, failure("InvalidPermissionProfile", "Permission capability decision is invalid")
            end
            matrix[capability] = decision
        end
        local matrix_digest, matrix_error = binding_digest(
            safety,
            "yaca-permission-matrix-v1",
            matrix_fields(matrix)
        )
        if not matrix_digest then return nil, matrix_error end
        local snapshot_digest, snapshot_error = binding_digest(safety, "yaca-permission-profile-v1", {
            { name = "name", value = spec.name },
            { name = "matrix_digest", value = matrix_digest },
            { name = "config_generation", value = spec.config_generation },
        })
        if not snapshot_digest then return nil, snapshot_error end
        local public, freeze_error = freeze(safety, {
            schema_version = "yaca-permission-profile-v1",
            name = spec.name,
            config_generation = spec.config_generation,
            matrix = matrix,
            matrix_digest = matrix_digest,
            snapshot_digest = snapshot_digest,
            description = spec.description,
            system_prompt = spec.system_prompt,
            authority = "local-effective-config-generation",
        }, "Permission profile")
        if not public then return nil, freeze_error end
        profiles[public] = {
            name = spec.name,
            config_generation = spec.config_generation,
            matrix = matrix,
            matrix_digest = matrix_digest,
            snapshot_digest = snapshot_digest,
        }
        return public
    end

    -- Evaluate one tool action against a registered profile and fixed capability map.
    --@param self table Permission service; private profile registry is captured here.
    --@param profile table Current-process profile returned by this service.
    --@param action table Tool, scope, reserved-tree, and review flags.
    --@return table|nil decision Immutable decision with private registered facts.
    --@return table|nil err Structured foreign-profile, action, or freeze failure.
    function service:evaluate(profile, action)
        local profile_state = profiles[profile]
        if not profile_state then
            return nil, failure("InvalidPermissionProfile", "profile was not created by this service")
        end
        if not exact_keys(action, {
            "tool", "outside_workspace", "reserved_tree", "double_check",
            "action_review_enabled",
        }) or not TOOLS[action.tool]
            or type(action.outside_workspace) ~= "boolean"
            or type(action.reserved_tree) ~= "boolean"
            or type(action.double_check) ~= "boolean"
            or type(action.action_review_enabled) ~= "boolean"
        then
            return nil, failure("InvalidPermissionAction", "Permission action is invalid")
        end
        local descriptor = TOOLS[action.tool]
        local required = copy_array(descriptor.caps)
        local outside_effective = descriptor.target_kind == "direct-path" and action.outside_workspace
        if outside_effective then required[#required + 1] = "OutsideWorkspace" end
        local rank = 0
        for _, capability in ipairs(required) do
            rank = math.max(rank, DECISION_RANK[profile_state.matrix[capability]])
        end
        local hard_denial
        if action.reserved_tree then
            rank = DECISION_RANK.deny
            hard_denial = "ReservedTree"
        end
        local decision = RANK_DECISION[rank]
        local review_required = descriptor.high_risk
            and action.double_check
            and action.action_review_enabled
            and decision ~= "deny"
        local public, freeze_error = freeze(safety, {
            schema_version = "yaca-permission-decision-v1",
            tool = action.tool,
            target_kind = descriptor.target_kind,
            required_capabilities = required,
            decision = decision,
            decision_rank = rank,
            profile_name = profile_state.name,
            profile_matrix_digest = profile_state.matrix_digest,
            profile_snapshot_digest = profile_state.snapshot_digest,
            config_generation = profile_state.config_generation,
            outside_workspace = action.outside_workspace,
            outside_workspace_effective = outside_effective,
            reserved_tree = action.reserved_tree,
            hard_denial = hard_denial or false,
            high_risk = descriptor.high_risk,
            double_check = action.double_check,
            action_review_enabled = action.action_review_enabled,
            review_required = review_required,
            review_status = review_required and "required" or "not-required",
            blocked = false,
            human_confirmation_required = decision == "confirm",
            shell_scope = PROCESS_TOOLS[action.tool] and "opaque-uncontained" or false,
        }, "Permission decision")
        if not public then return nil, freeze_error end
        decisions[public] = {
            tool = action.tool,
            target_kind = descriptor.target_kind,
            required_capabilities = required,
            decision = decision,
            decision_rank = rank,
            profile_name = profile_state.name,
            profile_matrix_digest = profile_state.matrix_digest,
            profile_snapshot_digest = profile_state.snapshot_digest,
            config_generation = profile_state.config_generation,
            outside_workspace = action.outside_workspace,
            outside_workspace_effective = outside_effective,
            reserved_tree = action.reserved_tree,
            hard_denial = hard_denial,
            high_risk = descriptor.high_risk,
            double_check = action.double_check,
            action_review_enabled = action.action_review_enabled,
            review_required = review_required,
            review_status = review_required and "required" or "not-required",
            blocked = false,
        }
        return public
    end

    -- Apply a review result without relaxing the original permission rank.
    --@param self table Permission service owning the decision registry.
    --@param decision table Current-process decision from this service.
    --@param reviewer_decision string allow, confirm, deny, or uncertain.
    --@return table|nil reviewed Immutable tightened or blocked decision.
    --@return table|nil err Structured foreign-decision, review, or freeze failure.
    function service:tighten(decision, reviewer_decision)
        local current = decisions[decision]
        if not current then
            return nil, failure("InvalidPermissionDecision", "decision was not created by this service")
        end
        if reviewer_decision ~= "uncertain" and DECISION_RANK[reviewer_decision] == nil then
            return nil, failure("InvalidReviewDecision", "reviewer decision is invalid")
        end
        local result = copy_map(current)
        if reviewer_decision == "uncertain" then
            result.blocked = true
            result.review_status = "uncertain"
        else
            result.decision_rank = math.max(current.decision_rank, DECISION_RANK[reviewer_decision])
            result.decision = RANK_DECISION[result.decision_rank]
            result.review_status = "reviewed"
        end
        local public_values = copy_map(result)
        public_values.schema_version = "yaca-permission-decision-v1"
        public_values.required_capabilities = copy_array(result.required_capabilities)
        public_values.hard_denial = result.hard_denial or false
        public_values.human_confirmation_required = not result.blocked
            and result.decision == "confirm"
        public_values.shell_scope = PROCESS_TOOLS[result.tool] and "opaque-uncontained" or false
        local public, freeze_error = freeze(safety, public_values, "reviewed Permission decision")
        if not public then return nil, freeze_error end
        decisions[public] = result
        return public
    end

    -- Bind a reviewed confirm decision to exact operation and workspace facts.
    --@param self table Permission service owning decisions and snapshots.
    --@param decision table Current-process reviewed confirm decision.
    --@param binding table Exact schema, tool, target, digest, cwd, and operation identities.
    --@return table|nil snapshot Immutable approval prompt evidence.
    --@return table|nil err Structured review, policy, binding, digest, or freeze failure.
    function service:approval_snapshot(decision, binding)
        local current = decisions[decision]
        if not current then
            return nil, failure("InvalidPermissionDecision", "decision was not created by this service")
        end
        if current.blocked or current.review_status == "required" then
            return nil, failure("ReviewRequired", "action review must finish before human approval")
        end
        if current.decision == "deny" then
            return nil, failure("PermissionDenied", "denied action cannot create an approval snapshot")
        end
        if current.decision ~= "confirm" then
            return nil, failure("ApprovalNotRequired", "allowed action does not require human approval")
        end
        if not exact_keys(binding, SNAPSHOT_FIELDS) then
            return nil, failure("InvalidApprovalSnapshot", "approval binding fields are invalid")
        end
        for _, name in ipairs(SNAPSHOT_FIELDS) do
            local maximum = limits.maximum_identity_bytes
            local allow_empty = false
            if name == "canonical_arguments" then maximum = limits.maximum_arguments_bytes
            elseif name == "canonical_target" then maximum, allow_empty = limits.maximum_target_bytes, true
            elseif name == "expected_raw_digest" then allow_empty = true
            elseif name == "cwd" then maximum = limits.maximum_target_bytes end
            if not valid_text(binding[name], maximum, allow_empty) then
                return nil, failure("InvalidApprovalSnapshot", "approval binding value is invalid", name)
            end
        end
        local digest_fields = {
            { name = "tool_name", value = current.tool },
            { name = "schema_version", value = binding.schema_version },
            { name = "registry_digest", value = binding.registry_digest },
            { name = "canonical_arguments", value = binding.canonical_arguments },
            { name = "canonical_target", value = binding.canonical_target },
            { name = "expected_raw_digest", value = binding.expected_raw_digest },
            { name = "cwd", value = binding.cwd },
            { name = "permission_name", value = current.profile_name },
            { name = "permission_matrix_digest", value = current.profile_matrix_digest },
            { name = "permission_snapshot_digest", value = current.profile_snapshot_digest },
            { name = "config_generation", value = current.config_generation },
            { name = "decision", value = current.decision },
            { name = "required_capabilities", value = table.concat(current.required_capabilities, ",") },
            { name = "outside_workspace", value = current.outside_workspace_effective },
            { name = "double_check", value = current.double_check },
            { name = "action_review_enabled", value = current.action_review_enabled },
            { name = "review_status", value = current.review_status },
            { name = "workspace_root_identity", value = binding.workspace_root_identity },
            { name = "operation_id", value = binding.operation_id },
            { name = "tool_call_id", value = binding.tool_call_id },
        }
        local snapshot_digest, snapshot_error = binding_digest(
            safety,
            "yaca-approval-snapshot-v1",
            digest_fields
        )
        if not snapshot_digest then return nil, snapshot_error end
        local public_values = copy_map(binding)
        public_values.schema_version = binding.schema_version
        public_values.snapshot_schema = "yaca-approval-snapshot-v1"
        public_values.snapshot_digest = snapshot_digest
        public_values.tool = current.tool
        public_values.required_capabilities = copy_array(current.required_capabilities)
        public_values.permission_name = current.profile_name
        public_values.permission_matrix_digest = current.profile_matrix_digest
        public_values.permission_snapshot_digest = current.profile_snapshot_digest
        public_values.config_generation = current.config_generation
        public_values.permission_decision = current.decision
        public_values.outside_workspace = current.outside_workspace_effective
        public_values.double_check = current.double_check
        public_values.action_review_enabled = current.action_review_enabled
        public_values.review_status = current.review_status
        public_values.shell_scope = PROCESS_TOOLS[current.tool] and "opaque-uncontained" or false
        local public, freeze_error = freeze(safety, public_values, "approval snapshot")
        if not public then return nil, freeze_error end
        snapshots[public] = {
            digest = snapshot_digest,
            tool = current.tool,
            operation_id = binding.operation_id,
            tool_call_id = binding.tool_call_id,
        }
        return public
    end

    -- Record one human response bound to a current-process approval snapshot.
    --@param self table Permission service owning the snapshot registry.
    --@param snapshot table Current-process approval snapshot.
    --@param approval_id string Unique bounded local response identity.
    --@param approval_decision string approved or rejected.
    --@return table|nil approval Immutable one-action approval record.
    --@return table|nil err Structured foreign-snapshot, input, or freeze failure.
    function service:record_approval(snapshot, approval_id, approval_decision)
        local snapshot_state = snapshots[snapshot]
        if not snapshot_state then
            return nil, failure("InvalidApprovalSnapshot", "approval snapshot is not current-process evidence")
        end
        if not valid_token(approval_id, limits.maximum_identity_bytes)
            or (approval_decision ~= "approved" and approval_decision ~= "rejected")
        then
            return nil, failure("InvalidApproval", "approval identity or decision is invalid")
        end
        local public, freeze_error = freeze(safety, {
            schema_version = "yaca-approval-v1",
            approval_id = approval_id,
            decision = approval_decision,
            snapshot_digest = snapshot_state.digest,
            operation_id = snapshot_state.operation_id,
            tool_call_id = snapshot_state.tool_call_id,
            provenance = "local-current-process",
            reusable = false,
        }, "approval")
        if not public then return nil, freeze_error end
        approvals[public] = {
            decision = approval_decision,
            snapshot_digest = snapshot_state.digest,
            operation_id = snapshot_state.operation_id,
            tool_call_id = snapshot_state.tool_call_id,
            consumed = false,
        }
        return public
    end

    -- Verify one approval against the current snapshot, optionally consuming it.
    --@param approval table Current-process approval record.
    --@param current_snapshot table Current-process operation snapshot to match.
    --@param consume boolean Whether successful authorization becomes single-use consumed.
    --@return table|nil authorization Immutable authorization evidence.
    --@return table|nil err Structured foreign, rejected, consumed, stale, or freeze failure.
    --@effect Marks the private approval consumed before freezing when consume is true.
    local function verify(approval, current_snapshot, consume)
        local approval_state = approvals[approval]
        if not approval_state then
            return nil, failure("ApprovalAuditOnly", "historical or foreign approval cannot authorize")
        end
        local snapshot_state = snapshots[current_snapshot]
        if not snapshot_state then
            return nil, failure("InvalidApprovalSnapshot", "current approval snapshot is invalid")
        end
        if approval_state.consumed then
            return nil, failure("ApprovalConsumed", "one-action approval was already consumed")
        end
        if approval_state.decision ~= "approved" then
            return nil, failure("ApprovalRejected", "human rejected the bound action")
        end
        if approval_state.snapshot_digest ~= snapshot_state.digest
            or approval_state.operation_id ~= snapshot_state.operation_id
            or approval_state.tool_call_id ~= snapshot_state.tool_call_id
        then
            return nil, failure("ApprovalStale", "approved operation snapshot is stale")
        end
        if consume then approval_state.consumed = true end
        return freeze(safety, {
            authorized = true,
            snapshot_digest = snapshot_state.digest,
            operation_id = snapshot_state.operation_id,
            tool_call_id = snapshot_state.tool_call_id,
            consumed = consume,
        }, consume and "consumed approval" or "verified approval")
    end

    -- Check an approval binding without consuming its one-action authority.
    --@param self table Permission service owning the approval registry.
    --@param approval table Current-process approval record.
    --@param current_snapshot table Snapshot that must match the approval exactly.
    --@return table|nil authorization Immutable non-consuming verification evidence.
    --@return table|nil err Structured approval or binding failure.
    function service:verify_approval(approval, current_snapshot)
        return verify(approval, current_snapshot, false)
    end

    -- Consume a matching approved response so it cannot authorize another action.
    --@param self table Permission service owning the approval registry.
    --@param approval table Current-process approval record.
    --@param current_snapshot table Snapshot that must match the approval exactly.
    --@return table|nil authorization Immutable consumed authorization evidence.
    --@return table|nil err Structured approval or binding failure.
    --@effect Marks matching private approval state consumed on success.
    function service:consume_approval(approval, current_snapshot)
        return verify(approval, current_snapshot, true)
    end

    -- Admit an allow decision only after all required action review is complete.
    --@param self table Permission service owning the decision registry.
    --@param decision table Current-process allow decision.
    --@return table|nil authorization Immutable permission-allow evidence.
    --@return table|nil err Structured foreign, blocked, denied, confirm, or freeze failure.
    function service:admit_without_approval(decision)
        local current = decisions[decision]
        if not current then
            return nil, failure("InvalidPermissionDecision", "decision was not created by this service")
        end
        if current.blocked then return nil, failure("ReviewUncertain", "action review is unresolved") end
        if current.review_status == "required" then
            return nil, failure("ReviewRequired", "high-risk action review is required")
        end
        if current.decision == "deny" then
            return nil, failure("PermissionDenied", "Permission policy denied the action")
        end
        if current.decision == "confirm" then
            return nil, failure("ApprovalRequired", "human approval is required")
        end
        return freeze(safety, {
            authorized = true,
            reason = "permission-allow",
            tool = current.tool,
            profile_snapshot_digest = current.profile_snapshot_digest,
        }, "Permission admission")
    end

    service.capabilities = assert(freeze(safety, {
        schema_version = "yaca-permission-v1",
        capabilities = CAPABILITIES,
        decisions = { "allow", "confirm", "deny" },
        tools = TOOL_ORDER,
        persistent_grants = false,
        os_sandbox = false,
        direct_network = false,
        shell_outside_workspace_containment = false,
        historical_approval_authority = false,
    }, "Permission capabilities"))
    service.limits = assert(freeze(safety, limits, "Permission limits"))
    return readonly(service, "Permission service")
end

return M
