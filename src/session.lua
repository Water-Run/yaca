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

---Creates the saved-session input owner over one typed AgentLoop.
-- Draft observation is captured when text is staged, so a delayed submission
-- cannot silently redirect itself to a newer Context generation or turn.
-- @param loop table Typed Runtime AgentLoop facade.
-- @param options table Contains maximum_draft_bytes.
-- @return table|nil session Readonly saved-session facade.
-- @return table|nil err Structured construction failure.
function M.new_agent_session(loop, options)
    if type(loop) ~= "table"
        or type(loop.status) ~= "function"
        or type(loop.submit_main) ~= "function"
        or type(loop.enqueue) ~= "function"
        or type(loop.steer) ~= "function"
        or type(loop.start_side) ~= "function"
        or type(loop.resolve_yield) ~= "function"
        or type(loop.reply) ~= "function"
        or type(loop.list_queue) ~= "function"
        or type(loop.drop_queue) ~= "function"
        or type(loop.edit_queue) ~= "function"
        or type(loop.reorder_queue) ~= "function"
        or type(loop.clear_queue) ~= "function"
        or type(loop.use_side) ~= "function"
        or type(loop.close) ~= "function"
    then
        return nil, failure("InvalidAgentSession", "a typed AgentLoop is required")
    end
    if type(options) ~= "table" then
        return nil, failure("InvalidSessionOptions", "saved-session limits are required")
    end
    for key in pairs(options) do
        if key ~= "maximum_draft_bytes" then
            return nil, failure("InvalidSessionOptions", "saved-session options are ambiguous")
        end
    end
    if not valid_integer(options.maximum_draft_bytes, 1) then
        return nil, failure("InvalidSessionOptions", "maximum_draft_bytes must be positive")
    end

    local lifecycle = "open"
    local staged
    local session = {}

    local function require_open()
        if lifecycle ~= "open" then
            return nil, failure("SessionClosed", "the saved Agent session is closed")
        end
        return true
    end

    local function observation(status)
        return {
            expected_context_generation = status.context_generation,
            expected_turn_id = status.turn_id,
        }
    end

    local function current_observation()
        return observation(loop:status())
    end

    local function command_from_draft()
        if not staged then return nil, failure("DraftEmpty", "no chat draft is staged") end
        return {
            text = staged.text,
            source = staged.source,
            expected_context_generation = staged.context_generation,
            expected_turn_id = staged.turn_id,
        }
    end

    local function consume_on_success(result, action_error)
        if not result then return nil, action_error end
        staged = nil
        return result
    end

    local function resolve_display(display_id)
        if type(display_id) ~= "string" or not display_id:match("^#[1-9][0-9]*$") then
            return nil, failure("InvalidQueueId", "queue display id is invalid")
        end
        local projection = loop:list_queue()
        for _, item in ipairs(projection.items) do
            if item.display_id == display_id then return item.queue_item_id end
        end
        return nil, failure("QueueItemMissing", "queue display id is not active")
    end

    ---Captures a bounded draft plus the exact Context/turn observation it saw.
    function session:stage(text_value, source)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        source = source or "user"
        if not valid_text(text_value, options.maximum_draft_bytes) or text_value == ""
            or type(source) ~= "string" or source == ""
        then
            return nil, failure("InvalidDraft", "saved-session draft is invalid")
        end
        local status = loop:status()
        staged = {
            text = text_value,
            source = source,
            context_generation = status.context_generation,
            turn_id = status.turn_id,
        }
        return self:draft()
    end

    ---Returns the detached current draft; its text is preserved on lane rejection.
    function session:draft()
        if not staged then return false end
        return readonly({
            text = staged.text,
            source = staged.source,
            context_generation = staged.context_generation,
            turn_id = staged.turn_id,
        }, "saved-session draft")
    end

    ---Submits staged text to reply, supersede-yield, direct-main, or queue by state.
    function session:submit()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local status = loop:status()
        local result, action_error
        if command.expected_context_generation ~= status.context_generation
            or command.expected_turn_id ~= status.turn_id
        then
            return nil, failure(
                "StaleDraftObservation",
                "draft was preserved because the active Context or turn changed"
            )
        elseif status.state == "Idle" then
            result, action_error = loop:submit_main(command)
        elseif status.state == "WaitingUser"
            and (status.pending_kind == "ask-user"
                or status.pending_kind == "termination-review")
        then
            result, action_error = loop:reply(command.text, command.source)
        elseif status.state == "WaitingUser" and status.pending_kind == "model-yield" then
            command.response_id = status.pending_response_id
            command.action = "supersede"
            result, action_error = loop:resolve_yield(command)
        else
            result, action_error = loop:enqueue(command)
        end
        return consume_on_success(result, action_error)
    end

    ---Explicit queue admission for the staged draft.
    function session:queue()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:enqueue(command)
        return consume_on_success(result, action_error)
    end

    ---Explicit same-turn steer for the staged draft.
    function session:steer()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:steer(command)
        return consume_on_success(result, action_error)
    end

    ---Explicit single-concurrency side request for the staged draft.
    function session:side()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:start_side(command)
        return consume_on_success(result, action_error)
    end

    ---Continues the exact yielded response in a new turn using the staged text.
    function session:continue_response(response_id)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        command.response_id = response_id
        command.action = "continue"
        local result, action_error = loop:resolve_yield(command)
        return consume_on_success(result, action_error)
    end

    function session:queue_list()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        return loop:list_queue()
    end

    function session:queue_drop(display_id, reason)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local queue_item_id, id_error = resolve_display(display_id)
        if not queue_item_id then return nil, id_error end
        local observed = current_observation()
        observed.queue_item_id = queue_item_id
        observed.reason = reason or "user-drop"
        return loop:drop_queue(observed)
    end

    function session:queue_edit(display_id, text_value)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        if not valid_text(text_value, options.maximum_draft_bytes) or text_value == "" then
            return nil, failure("InvalidDraft", "queue amendment text is invalid")
        end
        local queue_item_id, id_error = resolve_display(display_id)
        if not queue_item_id then return nil, id_error end
        local observed = current_observation()
        observed.queue_item_id = queue_item_id
        observed.text = text_value
        return loop:edit_queue(observed)
    end

    function session:queue_move(display_id, before_display_id)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local queue_item_id, id_error = resolve_display(display_id)
        if not queue_item_id then return nil, id_error end
        local before_queue_item_id = false
        if before_display_id ~= false then
            before_queue_item_id, id_error = resolve_display(before_display_id)
            if not before_queue_item_id then return nil, id_error end
        end
        local observed = current_observation()
        observed.queue_item_id = queue_item_id
        observed.before_queue_item_id = before_queue_item_id
        return loop:reorder_queue(observed)
    end

    function session:queue_clear(reason)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local observed = current_observation()
        observed.reason = reason or "user-clear"
        return loop:clear_queue(observed)
    end

    function session:use_side(side_id, lane)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local observed = current_observation()
        observed.side_id = side_id
        observed.lane = lane
        return loop:use_side(observed)
    end

    function session:clear_draft()
        local existed = staged ~= nil
        staged = nil
        return existed
    end

    function session:status()
        return readonly({
            lifecycle = lifecycle,
            has_draft = staged ~= nil,
            draft = self:draft(),
            loop = loop:status(),
        }, "saved Agent session status")
    end

    function session:close(reason)
        if lifecycle ~= "open" then return false end
        local closed, close_error = loop:close(reason or "session-close")
        if closed == nil then return nil, close_error end
        lifecycle = "closed"
        staged = nil
        return true
    end

    return readonly(session, "saved Agent session")
end

return M
