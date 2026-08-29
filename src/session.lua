--[[
File: session.lua
Date: 2026-08-29
Author: WaterRun
Description: Owns the bounded unsaved chat draft before Context publication.
]]

local text = require("text")

local M = {}

local function failure(code, message)
    return { code = code, message = message }
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

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function valid_text(value, maximum_bytes)
    if type(value) ~= "string" or #value > maximum_bytes then return false end
    local valid, metadata = text.validate_utf8(value)
    return valid and not metadata.contains_nul
end

local function validate_workspace(workspace)
    if type(workspace) ~= "table"
        or type(workspace.path) ~= "string"
        or workspace.path == ""
        or workspace.enterable ~= true
    then
        return nil, failure(
            "InvalidWorkspace",
            "unsaved chat requires a validated enterable workspace"
        )
    end
    return {
        path = workspace.path,
        identity = workspace.identity,
    }
end

local function validate_generation(generation)
    if type(generation) ~= "table"
        or type(generation.id) ~= "string"
        or generation.id == ""
        or generation.agent_ready ~= true
        or type(generation.current_model) ~= "string"
        or type(generation.current_permission) ~= "string"
        or type(generation.models) ~= "table"
        or type(generation.permissions) ~= "table"
        or type(generation.scan_registered_secrets) ~= "function"
    then
        return nil, failure(
            "ModelUnavailable",
            "unsaved chat requires an Agent-ready configuration generation"
        )
    end
    return generation
end

local function settings_bytes(settings)
    return #settings.model
        + #settings.permission
        + #settings.double_check_goal
        + #settings.context_prompt
end

---Creates a bounded in-memory chat draft without scanning or writing Contexts.
-- The draft owns only not-yet-durable session selectors. It cannot accept a
-- first main message until the later Context publication service is attached.
-- @param generation table Immutable Agent-ready ConfigGeneration.
-- @param workspace table Validated path/identity/enterable observation.
-- @param options table Contains maximum_draft_bytes.
-- @return table|nil draft Immutable facade over the owned draft state.
-- @return table|nil err Structured validation failure.
function M.new_draft(generation, workspace, options)
    local admitted_generation, generation_error = validate_generation(generation)
    if not admitted_generation then return nil, generation_error end
    local admitted_workspace, workspace_error = validate_workspace(workspace)
    if not admitted_workspace then return nil, workspace_error end
    if type(options) ~= "table" then
        return nil, failure("InvalidSessionOptions", "session limits are required")
    end
    for key in pairs(options) do
        if key ~= "maximum_draft_bytes" then
            return nil, failure("InvalidSessionOptions", "session options contain an unknown field")
        end
    end
    if not valid_integer(options.maximum_draft_bytes, 1) then
        return nil, failure("InvalidSessionOptions", "maximum_draft_bytes must be positive")
    end
    if not valid_text(generation.context_prompt or "", options.maximum_draft_bytes) then
        return nil, failure("DraftLimit", "initial Context Prompt exceeds the draft limit")
    end

    local lifecycle = "not-saved"
    local settings = {
        model = generation.current_model,
        permission = generation.current_permission,
        double_check = generation.effective_double_check,
        double_check_goal = generation.effective_double_check_goal or "",
        context_prompt = generation.context_prompt or "",
        auto_rename_disabled = generation.auto_rename_disabled == true,
    }
    if settings_bytes(settings) > options.maximum_draft_bytes then
        return nil, failure("DraftLimit", "initial session settings exceed the draft limit")
    end
    local draft = {}

    local function require_open()
        if lifecycle ~= "not-saved" then
            return nil, failure("SessionClosed", "the unsaved chat draft is closed")
        end
        return true
    end

    local function status()
        return readonly({
            lifecycle = lifecycle,
            durable = false,
            context_path = false,
            context_hash = false,
            display_name = "not saved",
            workspace = admitted_workspace.path,
            config_generation = generation.id,
            model = settings.model,
            permission = settings.permission,
            double_check = settings.double_check,
            double_check_goal = settings.double_check_goal,
            context_prompt = settings.context_prompt,
            auto_rename_disabled = settings.auto_rename_disabled,
        }, "session status")
    end

    ---Returns a fresh immutable projection of the owned draft state.
    function draft.status()
        return status()
    end

    ---Updates only session-whitelisted settings before the first main message.
    -- @param changes table Model, Permission, DoubleCheck, goal, and Prompt fields.
    -- @return table|nil status New immutable draft projection.
    -- @return table|nil err Unknown, invalid, or closed-state failure.
    function draft.update(changes)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        if type(changes) ~= "table" then
            return nil, failure("InvalidDraftUpdate", "draft changes must be a table")
        end
        local allowed = {
            model = true,
            permission = true,
            double_check = true,
            double_check_goal = true,
            context_prompt = true,
            auto_rename_disabled = true,
        }
        for key in pairs(changes) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidDraftUpdate", "draft update contains an unknown field")
            end
        end
        local next_settings = {}
        for key, value in pairs(settings) do next_settings[key] = value end
        if changes.model ~= nil then
            local model = type(changes.model) == "string"
                and generation.models[changes.model]
                or nil
            if not model or not model.enabled or not model.tools_enabled then
                return nil, failure("ModelUnavailable", "draft Model is unavailable")
            end
            next_settings.model = changes.model
        end
        if changes.permission ~= nil then
            if type(changes.permission) ~= "string"
                or not generation.permissions[changes.permission]
            then
                return nil, failure("PermissionUnavailable", "draft Permission is unavailable")
            end
            next_settings.permission = changes.permission
        end
        if changes.double_check ~= nil then
            if type(changes.double_check) ~= "boolean" then
                return nil, failure("InvalidDraftUpdate", "double_check must be boolean")
            end
            next_settings.double_check = changes.double_check
        end
        for _, key in ipairs({ "double_check_goal", "context_prompt" }) do
            if changes[key] ~= nil then
                if not valid_text(changes[key], options.maximum_draft_bytes) then
                    return nil, failure("DraftLimit", key .. " exceeds the draft limit")
                end
                local hits, scan_error = generation.scan_registered_secrets(changes[key])
                if not hits then return nil, scan_error end
                if #hits > 0 then
                    return nil, failure(
                        "RegisteredSecret",
                        key .. " matches a registered configuration secret"
                    )
                end
                next_settings[key] = changes[key]
            end
        end
        if changes.auto_rename_disabled ~= nil then
            if type(changes.auto_rename_disabled) ~= "boolean" then
                return nil, failure(
                    "InvalidDraftUpdate",
                    "auto_rename_disabled must be boolean"
                )
            end
            next_settings.auto_rename_disabled = changes.auto_rename_disabled
        end
        if settings_bytes(next_settings) > options.maximum_draft_bytes then
            return nil, failure("DraftLimit", "session settings exceed the draft limit")
        end
        settings = next_settings
        return status()
    end

    ---Refuses a first main message until durable Context publication is wired.
    -- @return nil
    -- @return table err Typed non-acceptance; no Model or tool has been started.
    function draft.begin_main()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        return nil, failure(
            "ContextPublicationUnavailable",
            "the first main message cannot be accepted before Context storage is attached"
        )
    end

    ---Closes the in-memory draft without creating any filesystem object.
    function draft.close()
        if lifecycle == "closed" then return false end
        lifecycle = "closed"
        return true
    end

    ---Returns the frozen generation used to create this draft.
    function draft.config_generation()
        return generation
    end

    return readonly(draft, "unsaved chat draft")
end

return M
