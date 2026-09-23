--[[
Author: WaterRun
Date: 2026-09-23
File: tui.lua
Description: Renders bounded append-only semantic transcript blocks.
]]

local cli = require("cli")
local terminal = require("terminal")
local text = require("text")

local M = {}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param extra table|nil Additional diagnostic fields copied after code/message and allowed to override them.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, extra)
    local result = { code = code, message = message }
    for key, value in pairs(extra or {}) do result[key] = value end
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
        __metatable = "locked",
    })
end

-- Copy nested registry tables while preserving repeated references and cycles.
--@param value any Registry value or table to detach.
--@param seen table|nil Recursion map of original tables to their copies.
--@return any copy Detached table graph or unchanged scalar.
local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[deep_copy(key, seen)] = deep_copy(item, seen) end
    return result
end

local BLOCK_ORDER = {
    "user", "assistant", "tool", "ask", "status", "queue", "steer",
    "notice", "warning", "error", "recovery", "details", "action",
}

local BLOCK_KINDS = {
    user = { label = "USER", id = false, color = "bright-white" },
    assistant = { label = "ASSISTANT", id = false, color = "cyan" },
    tool = { label = "TOOL", id = true, color = "cyan" },
    ask = { label = "ASK", id = true, color = "magenta" },
    status = { label = "STATUS", id = false, color = "dim-neutral" },
    queue = { label = "QUEUE", id = true, color = "cyan" },
    steer = { label = "STEER", id = true, color = "yellow" },
    notice = { label = "NOTICE", id = false, color = "cyan" },
    warning = { label = "WARNING", id = false, color = "yellow" },
    error = { label = "ERROR", id = true, color = "red" },
    recovery = { label = "RECOVERY", id = true, color = "red" },
    details = { label = "DETAILS", id = true, color = "cyan" },
    action = { label = "ACTION", id = true, color = "yellow" },
}

local TRANSCRIPT_BLOCKS = {}
for _, kind in ipairs(BLOCK_ORDER) do
    local specification = BLOCK_KINDS[kind]
    TRANSCRIPT_BLOCKS[#TRANSCRIPT_BLOCKS + 1] = specification.label
        .. (specification.id and " ID" or "")
end

local PROMPTS = {
    chat = { text = ">>", color = "dim-neutral" },
    approval = { text = "??", color = "yellow" },
    model_repl = { text = "model>", color = "green" },
    config_repl = { text = "config>", color = "cyan" },
    context_repl = { text = "context>", color = "blue" },
    self_test = { text = "test>", color = "magenta" },
}

local INPUT_BINDINGS = {
    { intent = "submit-or-queue", key = "Enter", fallback_action = "queue-add" },
    { intent = "steer", key = "Ctrl+Enter", fallback_action = "steer" },
    { intent = "newline", key = "Shift+Enter", fallback_action = "multiline" },
    { intent = "ask", key = "Alt+Enter", fallback_action = "ask" },
    { intent = "cancel", key = "Esc", fallback_action = "cancel" },
}

local TUI_REGISTRY = {
    contract_version = "0.1.0-readiness.1",
    decision_refs = { "D-054", "D-064", "D-066" },
    product_slogan = "yaca: General-purpose terminal agent.",
    prompts = PROMPTS,
    plain_text_uses_same_prompt_text = true,
    input_bindings = INPUT_BINDINGS,
    input_states = {
        "line-edit", "multiline-edit", "busy-input", "waiting-user-answer",
        "approval-answer", "selector", "repl-line", "closing",
    },
    runtime_state_projection = {
        Idle = "line-edit",
        Preparing = "busy-input",
        RequestingModel = "busy-input",
        Streaming = "busy-input",
        DispatchingTools = "busy-input",
        AwaitingApproval = "approval-answer",
        ExecutingTool = "busy-input",
        EvaluatingAction = "busy-input",
        EvaluatingTermination = "busy-input",
        WaitingUser = "waiting-user-answer",
        Finalizing = "busy-input",
        Closing = "closing",
    },
    renderer_gestures_not_domain_actions = {
        "cursor-left", "cursor-right", "cursor-up", "cursor-down", "scroll-up",
        "scroll-down", "page-up", "page-down", "focus-next",
    },
    output = {
        startup_lines_independent = true,
        startup_master_switch = false,
        mandatory_prefixes = { "ERROR", "WARNING", "ACTION", "STATUS" },
        context_hash = "16-uppercase-hex",
        queue_id = "#N",
        stdout_is_primary_result = true,
        stderr_is_diagnostics = true,
        renderer = "append-only-transcript-with-optional-current-status-enhancement",
        interactive_gate = "stdin-and-stdout-are-tty-and-machine-not-requested",
        program_chrome = "ASCII-only",
        untrusted_control_bytes = "escape-before-render",
        transcript_fixture = "fixtures/tui-transcripts.lua",
    },
    line_editor = {
        ownership = "yaca-native-or-raw-editor",
        draft_is_runtime_owned = true,
        async_output = "atomically-hide-draft-append-complete-block-redraw-identical-draft",
        character_level_interleave = false,
        cooked_fallback = "coalesce-and-defer-until-safe-line-with-visible-backlog-status",
        plain_mode_semantics_equal = true,
    },
    transcript_blocks = TRANSCRIPT_BLOCKS,
    block_kinds = BLOCK_KINDS,
    terminal_modes = {
        enhanced = "capability-detected",
        plain_tty = "full-text-command-fallback",
        dumb_or_no_color = "same-ASCII-prompts-no-color",
        non_tty_chat = "reject-interactive-chat",
        windows_xp_ansi_assumed = false,
    },
    proof_required = {
        "TP-003-console-input-event-pump",
        "TP-015-render-and-key-fallback",
    },
}

local SEMANTIC_ACTIONS = cli.registry()
local ACTION_BY_ID = {}
local FALLBACK_COMMAND = {}
for _, descriptor in ipairs(SEMANTIC_ACTIONS.actions) do
    ACTION_BY_ID[descriptor.id] = descriptor
    for _, projection in ipairs(descriptor.projections) do
        if projection.kind == "chat-line" then
            FALLBACK_COMMAND[descriptor.id] = projection.command
        end
    end
end
for _, binding in ipairs(INPUT_BINDINGS) do
    if not ACTION_BY_ID[binding.fallback_action]
        or not FALLBACK_COMMAND[binding.fallback_action]
    then
        error("TUI input fallback is absent from the semantic action registry")
    end
end

local ANSI_CODES = {
    ["bright-white"] = "97",
    ["dim-neutral"] = "90",
    red = "31",
    green = "32",
    yellow = "33",
    blue = "34",
    magenta = "35",
    cyan = "36",
}

local INPUT_BY_INTENT = {}
for _, binding in ipairs(INPUT_BINDINGS) do INPUT_BY_INTENT[binding.intent] = binding end

local STARTUP_FIELDS = {
    { id = "slogan", fixed = TUI_REGISTRY.product_slogan },
    { id = "version", label = "version" },
    { id = "work_directory", label = "work directory" },
    { id = "data_root", label = "data root" },
    { id = "config_status", label = "config" },
    { id = "context", label = "context" },
    { id = "context_hash", label = "context hash" },
    { id = "model", label = "model" },
    { id = "permission", label = "permission" },
    { id = "double_check", label = "double check" },
    { id = "status_hint", fixed = "Run .status for details." },
}

local STARTUP_FIELD_BY_ID = {}
for _, field in ipairs(STARTUP_FIELDS) do STARTUP_FIELD_BY_ID[field.id] = field end

-- Require visible ASCII-only text for renderer-owned labels and prompts.
--@param value any Candidate program chrome string.
--@return boolean valid Whether every byte is printable ASCII.
local function ascii_chrome(value)
    if type(value) ~= "string" or value == "" then return false end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 0x20 or byte > 0x7E then return false end
    end
    return true
end

if not ascii_chrome(TUI_REGISTRY.product_slogan) then error("TUI slogan must be ASCII") end
for _, specification in pairs(BLOCK_KINDS) do
    if not ascii_chrome(specification.label) then error("TUI block label must be ASCII") end
end
for _, prompt in pairs(PROMPTS) do
    if not ascii_chrome(prompt.text) then error("TUI prompt must be ASCII") end
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Prefix untrusted text that could impersonate a transcript block or prompt.
--@param line string Already escaped single display line.
--@return string protected Literal line, backslash-prefixed when it resembles chrome.
local function protect_chrome(line)
    if line:match("^%[[A-Z][^%]]*%]") then return "\\" .. line end
    for _, prompt in pairs(PROMPTS) do
        if line:sub(1, #prompt.text) == prompt.text then
            local following = line:sub(#prompt.text + 1, #prompt.text + 1)
            if following == "" or following == " " or following == "\t" then
                return "\\" .. line
            end
        end
    end
    for _, prefix in ipairs({
        "yaca:", "yaca ", "version:", "work directory:", "data root:",
        "config:", "context:", "context hash:", "model:", "permission:",
        "double check:", "Run .status for details.",
    }) do
        if line:sub(1, #prefix) == prefix then return "\\" .. line end
    end
    return line
end

-- Identify Unicode format and directional controls that must be visible.
--@param codepoint integer Decoded Unicode scalar value.
--@return boolean control Whether this scalar is in a hidden-control range.
local function is_unicode_control(codepoint)
    return (codepoint >= 0x200B and codepoint <= 0x200F)
        or (codepoint >= 0x2028 and codepoint <= 0x202E)
        or (codepoint >= 0x2060 and codepoint <= 0x206F)
        or codepoint == 0xFEFF
end

-- Render strict UTF-8 content on one safe line with control and chrome escaping.
--@param source any Candidate untrusted display text.
--@param ascii_only boolean Whether non-ASCII scalars use visible escape syntax.
--@return string|nil escaped Safe single-line display bytes.
--@return table|nil err Structured type or UTF-8 failure with source offset.
local function escape_inline(source, ascii_only)
    if type(source) ~= "string" then
        return nil, failure("InvalidViewText", "view text must be a string")
    end
    local codepoints, decoding_error = text.decode_utf8(source)
    if not codepoints then
        return nil, failure("InvalidViewText", "view text must be strict UTF-8", {
            reason = decoding_error.reason,
            offset = decoding_error.offset,
        })
    end
    local parts = {}
    for _, codepoint in ipairs(codepoints) do
        if codepoint == 0x09 then
            parts[#parts + 1] = "\\t"
        elseif codepoint == 0x0A then
            parts[#parts + 1] = "\\n"
        elseif codepoint == 0x0D then
            parts[#parts + 1] = "\\r"
        elseif codepoint < 0x20 or codepoint == 0x7F then
            parts[#parts + 1] = string.format("\\x%02X", codepoint)
        elseif codepoint >= 0x80 and codepoint <= 0x9F then
            parts[#parts + 1] = string.format("\\u{%04X}", codepoint)
        elseif is_unicode_control(codepoint) then
            parts[#parts + 1] = string.format("\\u{%04X}", codepoint)
        elseif ascii_only and codepoint > 0x7F then
            parts[#parts + 1] = string.format("\\u{%X}", codepoint)
        else
            parts[#parts + 1] = assert(text.encode_scalar(codepoint))
        end
    end
    return protect_chrome(table.concat(parts))
end

-- Split semantic block content on LF while preserving empty trailing lines.
--@param source string Exact block text bytes.
--@return table lines Ordered source-line strings without LF bytes.
local function split_text(source)
    local lines = {}
    local start_index = 1
    while true do
        local newline = source:find("\n", start_index, true)
        if not newline then
            lines[#lines + 1] = source:sub(start_index)
            break
        end
        lines[#lines + 1] = source:sub(start_index, newline - 1)
        start_index = newline + 1
    end
    return lines
end

-- Validate and copy a dense string sequence used as block content.
--@param values any Candidate line sequence.
--@return table|nil lines Independent ordered string sequence.
--@return table|nil err Structured sparse, key, or element-type failure.
local function dense_lines(values)
    if type(values) ~= "table" then
        return nil, failure("InvalidViewBlock", "block lines must be a dense array")
    end
    local count, maximum = 0, 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then
            return nil, failure("InvalidViewBlock", "block lines must be a dense array")
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then
        return nil, failure("InvalidViewBlock", "block lines must be a dense array")
    end
    local result = {}
    for index = 1, count do
        if type(values[index]) ~= "string" then
            return nil, failure("InvalidViewBlock", "block lines must contain strings")
        end
        result[index] = values[index]
    end
    return result
end

-- Admit a bounded canonical transcript identifier in one fixed ASCII form.
--@param value any Candidate block identifier.
--@param maximum_bytes integer Inclusive ID byte cap.
--@return boolean valid Whether the ID can appear in program chrome.
local function valid_id(value, maximum_bytes)
    if type(value) ~= "string" or value == "" or #value > maximum_bytes then return false end
    if value:match("^#[1-9][0-9]*$") then return true end
    if value:match("^[A-Za-z0-9][A-Za-z0-9._%-]*$") then return true end
    if value:match("^[A-Za-z][A-Za-z0-9_%-]*:[A-Za-z0-9][A-Za-z0-9._%-]*$") then
        return true
    end
    return false
end

-- Wrap trusted renderer-owned text in a fixed ANSI color sequence when enabled.
--@param enabled boolean Whether ANSI color output is allowed.
--@param color string Fixed semantic color key from ANSI_CODES.
--@param value string Trusted block label or prompt bytes.
--@return string styled Colored or unchanged text.
local function colorize(enabled, color, value)
    if not enabled then return value end
    return "\27[" .. ANSI_CODES[color] .. "m" .. value .. "\27[0m"
end

-- Snapshot terminal color, Unicode, and fixed key facts from the backend.
--@param value any Candidate terminal capability record.
--@return table|nil capabilities Independent admitted fact table.
--@return table|nil err Structured missing, unknown, or ill-typed fact failure.
local function validate_capabilities(value)
    if type(value) ~= "table" then
        return nil, failure("InvalidTuiCapabilities", "terminal capabilities are required")
    end
    local allowed = { ansi = true, color = true, unicode = true, keys = true }
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidTuiCapabilities",
                "terminal capabilities contain an unknown field"
            )
        end
    end
    if type(value.ansi) ~= "boolean"
        or type(value.color) ~= "boolean"
        or type(value.unicode) ~= "boolean"
        or type(value.keys) ~= "table"
    then
        return nil, failure(
            "InvalidTuiCapabilities",
            "ansi, color, unicode, and key facts are required"
        )
    end
    local admitted_keys = {}
    local allowed_keys = {
        Enter = true,
        ["Ctrl+Enter"] = true,
        ["Shift+Enter"] = true,
        ["Alt+Enter"] = true,
        Esc = true,
    }
    for key, available in pairs(value.keys) do
        if not allowed_keys[key] or type(available) ~= "boolean" then
            return nil, failure("InvalidTuiCapabilities", "key capability is invalid")
        end
        admitted_keys[key] = available
    end
    for key in pairs(allowed_keys) do
        if admitted_keys[key] == nil then
            return nil, failure("InvalidTuiCapabilities", "every fixed key fact is required")
        end
    end
    return {
        ansi = value.ansi,
        color = value.color,
        unicode = value.unicode,
        keys = admitted_keys,
    }
end

-- Copy and cross-check the three renderer hard byte limits.
--@param options table Validated constructor options with positive limit fields.
--@return table|nil limits Independent renderer limit table.
--@return table|nil err Structured missing or inconsistent limit failure.
local function validate_limits(options)
    local names = { "maximum_block_bytes", "maximum_line_bytes", "maximum_id_bytes" }
    local result = {}
    for _, name in ipairs(names) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidTuiLimits", name .. " must be a positive integer")
        end
        result[name] = options[name]
    end
    if result.maximum_line_bytes > result.maximum_block_bytes then
        return nil, failure(
            "InvalidTuiLimits",
            "maximum_line_bytes cannot exceed maximum_block_bytes"
        )
    end
    return result
end

-- Reject any already rendered line or block above its byte cap.
--@param lines table Sequence of complete rendered lines without LF separators.
--@param rendered string Complete block bytes including final newline when present.
--@param limits table Validated line and block byte caps.
--@return string|nil admitted Exact rendered bytes on success.
--@return table|nil err Structured line or block limit failure.
local function check_render_limits(lines, rendered, limits)
    for _, line in ipairs(lines) do
        if #line > limits.maximum_line_bytes then
            return nil, failure("TuiLimit", "rendered line exceeds maximum_line_bytes")
        end
    end
    if #rendered > limits.maximum_block_bytes then
        return nil, failure("TuiLimit", "rendered block exceeds maximum_block_bytes")
    end
    return rendered
end

-- Render one validated semantic block as escaped append-only transcript bytes.
--@param block table Candidate kind, ID, sequence, and text/lines carrier.
--@param capabilities table Snapshot of ANSI/color and Unicode display facts.
--@param limits table Validated ID, line, and block byte caps.
--@return string|nil rendered Complete block bytes with trailing newline.
--@return table|nil err Structured shape, text, ID, or size failure.
local function render_block(block, capabilities, limits)
    if type(block) ~= "table" then
        return nil, failure("InvalidViewBlock", "semantic block must be a table")
    end
    local allowed = {
        kind = true, id = true, text = true, lines = true, inline = true, sequence = true,
    }
    for key in pairs(block) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidViewBlock", "semantic block contains an unknown field")
        end
    end
    local specification = BLOCK_KINDS[block.kind]
    if not specification then
        return nil, failure("InvalidViewBlock", "semantic block kind is unknown")
    end
    if specification.id then
        if not valid_id(block.id, limits.maximum_id_bytes) then
            return nil, failure("InvalidViewBlock", "semantic block requires one safe canonical ID")
        end
    elseif block.id ~= nil then
        return nil, failure("InvalidViewBlock", "this semantic block kind cannot display an ID")
    end
    if block.sequence ~= nil and not valid_integer(block.sequence, 1) then
        return nil, failure("InvalidViewBlock", "semantic block sequence must be positive")
    end
    if block.inline ~= nil and type(block.inline) ~= "boolean" then
        return nil, failure("InvalidViewBlock", "semantic block inline flag must be boolean")
    end
    if block.text ~= nil and block.lines ~= nil then
        return nil, failure("InvalidViewBlock", "semantic block has two content carriers")
    end

    local source_lines
    if block.text ~= nil then
        if type(block.text) ~= "string" then
            return nil, failure("InvalidViewBlock", "semantic block text must be a string")
        end
        source_lines = split_text(block.text)
    elseif block.lines ~= nil then
        local lines, lines_error = dense_lines(block.lines)
        if not lines then return nil, lines_error end
        source_lines = lines
    else
        source_lines = {}
    end
    if block.inline and #source_lines ~= 1 then
        return nil, failure("InvalidViewBlock", "inline semantic block requires one line")
    end

    local escaped_lines = {}
    for _, line in ipairs(source_lines) do
        local escaped, escape_error = escape_inline(line, not capabilities.unicode)
        if not escaped then return nil, escape_error end
        escaped_lines[#escaped_lines + 1] = escaped
    end
    local header = "[" .. specification.label
        .. (specification.id and (" " .. block.id) or "") .. "]"
    local styled_header = colorize(
        capabilities.ansi and capabilities.color,
        specification.color,
        header
    )
    local rendered_lines
    if block.inline then
        rendered_lines = { styled_header .. " " .. escaped_lines[1] }
    else
        rendered_lines = { styled_header }
        for _, line in ipairs(escaped_lines) do rendered_lines[#rendered_lines + 1] = line end
    end
    local rendered = table.concat(rendered_lines, "\n") .. "\n"
    return check_render_limits(rendered_lines, rendered, limits)
end

-- Admit independent startup values and visibility flags for every fixed field.
--@param snapshot table Candidate startup value map.
--@param visibility table Required boolean visibility map.
--@return table|nil admitted_snapshot Independent value map.
--@return table|nil visibility_or_err Independent flag map or structured failure.
local function validate_startup(snapshot, visibility)
    if type(snapshot) ~= "table" or type(visibility) ~= "table" then
        return nil, failure("InvalidStartupView", "startup snapshot and visibility are required")
    end
    local admitted_snapshot = {}
    for key, value in pairs(snapshot) do
        local field = STARTUP_FIELD_BY_ID[key]
        if type(key) ~= "string" or not field or field.fixed then
            return nil, failure("InvalidStartupView", "startup snapshot contains an unknown field")
        end
        admitted_snapshot[key] = value
    end
    local admitted_visibility = {}
    for key, value in pairs(visibility) do
        if type(key) ~= "string" or not STARTUP_FIELD_BY_ID[key]
            or type(value) ~= "boolean"
        then
            return nil, failure("InvalidStartupView", "startup visibility is invalid")
        end
        admitted_visibility[key] = value
    end
    for _, field in ipairs(STARTUP_FIELDS) do
        if admitted_visibility[field.id] == nil then
            return nil, failure(
                "InvalidStartupView",
                "every independent startup visibility fact is required"
            )
        end
        if admitted_visibility[field.id] and not field.fixed
            and admitted_snapshot[field.id] == nil
        then
            return nil, failure(
                "InvalidStartupView",
                "visible startup field is absent: " .. field.id
            )
        end
    end
    return admitted_snapshot, admitted_visibility
end

-- Format and validate one startup value for its fixed field role.
--@param field table Fixed startup field descriptor.
--@param value any Candidate value from the startup snapshot.
--@return string|nil formatted Display value, or nil when invalid.
local function startup_value(field, value)
    if field.id == "double_check" then
        if type(value) == "boolean" then return value and "on" or "off" end
        if value ~= "on" and value ~= "off" then return nil end
        return value
    end
    if type(value) ~= "string" then return nil end
    if field.id == "context_hash" and not value:match("^[0-9A-F][0-9A-F]+$") then
        return nil
    end
    if field.id == "context_hash" and #value ~= 16 then return nil end
    return value
end

-- Write one complete transcript block through an optional injected writer.
--@param writer function|table|nil Callback or object with write method; nil discards output.
--@param bytes string Complete validated block bytes.
--@return boolean|nil written True after full acceptance or when no writer is set.
--@return table|nil err BrokenStdout with output_unknown on partial/exception failure.
--@effect Calls the writer, which may have externally visible partial output.
local function write_chunk(writer, bytes)
    if not writer then return true end
    local called, result, writer_error
    if type(writer) == "function" then
        called, result, writer_error = pcall(writer, bytes)
    else
        called, result, writer_error = pcall(writer.write, writer, bytes)
    end
    if not called or (result ~= true and result ~= #bytes) then
        return nil, failure("BrokenStdout", "transcript output could not be completed", {
            output_unknown = true,
            reason = called and tostring(writer_error or "write failed")
                or "writer raised an exception",
        })
    end
    return true
end

---Returns a detached copy of the TUI semantic projection registry.
--@param none No arguments.
--@return table registry Deep copy of fixed TUI action and rendering metadata.
function M.registry()
    return deep_copy(TUI_REGISTRY)
end

---Creates a bounded renderer from explicit terminal facts and hard limits.
--@param options table Width, capabilities, limits, and optional append writer.
--@return table|nil renderer Immutable renderer facade.
--@return table|nil err Structured construction failure.
function M.new(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidTuiOptions", "TUI options are required")
    end
    local allowed = {
        width = true,
        capabilities = true,
        maximum_block_bytes = true,
        maximum_line_bytes = true,
        maximum_id_bytes = true,
        writer = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidTuiOptions", "TUI options contain an unknown field")
        end
    end
    if not valid_integer(options.width, 1) then
        return nil, failure("InvalidTuiOptions", "terminal width must be positive")
    end
    local capabilities, capabilities_error = validate_capabilities(options.capabilities)
    if not capabilities then return nil, capabilities_error end
    local limits, limits_error = validate_limits(options)
    if not limits then return nil, limits_error end
    local writer = options.writer
    if writer ~= nil and type(writer) ~= "function"
        and (type(writer) ~= "table" or type(writer.write) ~= "function")
    then
        return nil, failure("InvalidTuiOptions", "writer must be a function or provide write")
    end

    local state = "open"
    local last_sequence = 0
    local output_unknown = false
    local service = {}

    ---Returns a detached registry copy.
    --@param none No arguments; uses the fixed module registry.
    --@return table registry Deep copy of semantic TUI metadata.
    function service.registry()
        return M.registry()
    end

    ---Escapes strict UTF-8 user/model/tool text for safe single-line display.
    --@param source string Candidate untrusted display text.
    --@return string|nil escaped Safe single-line text for this terminal profile.
    --@return table|nil err Structured type or UTF-8 failure.
    function service.escape(source)
        return escape_inline(source, not capabilities.unicode)
    end

    ---Renders one semantic block without mutating append state.
    --@param block table Candidate semantic transcript block.
    --@return string|nil rendered Complete escaped block bytes.
    --@return table|nil err Structured block or limit failure.
    function service.render_block(block)
        return render_block(block, capabilities, limits)
    end

    ---Appends exactly one complete semantic block to the configured writer.
    --@param block table Candidate semantic block with optional increasing sequence.
    --@return string|nil rendered Complete block bytes after a successful append.
    --@return table|nil err Structured render, ordering, or output failure.
    --@effect Writes to the configured output, advances the sequence, or faults on uncertain output.
    function service.append(block)
        if state ~= "open" then
            return nil, failure("RendererClosed", "transcript renderer is " .. state)
        end
        local rendered, render_error = render_block(block, capabilities, limits)
        if not rendered then return nil, render_error end
        local sequence = block.sequence or (last_sequence + 1)
        if sequence <= last_sequence then
            return nil, failure(
                "OutOfOrderViewBlock",
                "append-only semantic sequence must increase"
            )
        end
        local written, write_error = write_chunk(writer, rendered)
        if not written then
            state = "faulted"
            output_unknown = true
            return nil, write_error
        end
        last_sequence = sequence
        return rendered
    end

    ---Creates a draft-safe editor whose output always uses this renderer.
    -- The returned facade does not expose the byte-level publish method, so an
    -- asynchronous producer can append only validated semantic blocks.
    --@param display table Terminal display port owned by the caller.
    --@param editor_options table Mode, focus, draft, backlog, and input caps.
    --@return table|nil facade Read-only semantic line editor facade.
    --@return table|nil err Structured options, prompt, renderer, or editor failure.
    --@ownership The facade retains the underlying editor and display until close.
    function service.new_line_editor(display, editor_options)
        if type(editor_options) ~= "table" then
            return nil, failure("InvalidLineEditor", "TUI line-editor options are required")
        end
        local allowed_editor_options = {
            mode = true,
            focus = true,
            maximum_draft_bytes = true,
            maximum_pending_bytes = true,
            maximum_pending_blocks = true,
            initial_draft = true,
            initial_cursor_byte = true,
        }
        for key in pairs(editor_options) do
            if type(key) ~= "string" or not allowed_editor_options[key] then
                return nil, failure(
                    "InvalidLineEditor",
                    "TUI line-editor options contain an unknown field"
                )
            end
        end
        local focus = editor_options.focus
        if not PROMPTS[focus] then
            return nil, failure("InvalidPrompt", "line-editor focus is unknown")
        end
        local backlog_notice, backlog_error = render_block({
            kind = "status",
            text = "output waiting",
            inline = true,
        }, capabilities, limits)
        if not backlog_notice then return nil, backlog_error end
        local line_editor, editor_error = terminal.new_line_editor(display, {
            mode = editor_options.mode,
            maximum_draft_bytes = editor_options.maximum_draft_bytes,
            maximum_pending_bytes = editor_options.maximum_pending_bytes,
            maximum_pending_blocks = editor_options.maximum_pending_blocks,
            initial_draft = editor_options.initial_draft,
            initial_cursor_byte = editor_options.initial_cursor_byte,
            -- Render the fixed focus prompt and the backend-owned draft safely.
            --@param draft string|boolean Backend draft, with false meaning no owned draft.
            --@return string|nil rendered Complete prompt line.
            --@return table|nil err Structured escaping or limit failure.
            render_prompt = function(draft)
                if draft == false or draft == "" then return service.render_prompt(focus) end
                return service.render_prompt(focus, draft)
            end,
            backlog_notice = backlog_notice,
        })
        if not line_editor then return nil, editor_error end

        local editor_sequence = 0
        local facade = {}

        -- Show the first prompt through the underlying terminal editor.
        --@param none Uses the captured editor instance.
        --@return boolean|nil shown True after the prompt is visible.
        --@return table|nil err Structured editor or display failure.
        --@effect May write or redraw the terminal prompt.
        function facade.show()
            return line_editor.show()
        end

        -- Replace the owned UTF-8 draft at a valid byte cursor.
        --@param value string Exact next draft bytes.
        --@param cursor_byte integer|nil Optional zero-based UTF-8 byte boundary.
        --@return table|nil snapshot Updated immutable editor facts.
        --@return table|nil err Structured edit or display failure.
        --@effect May redraw the owned terminal draft.
        function facade.set_draft(value, cursor_byte)
            return line_editor.set_draft(value, cursor_byte)
        end

        -- Insert strict UTF-8 text at the owned draft cursor.
        --@param value string Text bytes to insert.
        --@return table|nil snapshot Updated immutable editor facts.
        --@return table|nil err Structured edit or display failure.
        --@effect May redraw the owned terminal draft.
        function facade.insert(value)
            return line_editor.insert(value)
        end

        -- Delete one Unicode scalar before the owned cursor.
        --@param none Uses the captured editor draft and cursor.
        --@return table|nil snapshot Updated immutable editor facts.
        --@return table|nil err Structured edit or display failure.
        --@effect May redraw the owned terminal draft.
        function facade.backspace()
            return line_editor.backspace()
        end

        -- Delete one Unicode scalar after the owned cursor.
        --@param none Uses the captured editor draft and cursor.
        --@return table|nil snapshot Updated immutable editor facts.
        --@return table|nil err Structured edit or display failure.
        --@effect May redraw the owned terminal draft.
        function facade.delete_forward()
            return line_editor.delete_forward()
        end

        -- Move the owned cursor by scalar or to a draft boundary.
        --@param direction string left, right, home, or end.
        --@return table|nil snapshot Updated immutable editor facts.
        --@return table|nil err Structured gesture or display failure.
        --@effect May redraw the terminal draft at the new cursor.
        function facade.move(direction)
            return line_editor.move(direction)
        end

        -- Apply one normalized terminal input event without executing its action.
        --@param event table Normalized user_action event from the terminal port.
        --@return table|nil result Editor snapshot, submission, or cancel intent.
        --@return table|nil err Structured input or display failure.
        --@effect Updates the owned draft or pending submission state.
        function facade.consume(event)
            return line_editor.consume(event)
        end

        -- Lease the exact current draft for a semantic submission intent.
        --@param intent string Registered submission action.
        --@return table|nil submission Immutable draft and generation lease.
        --@return table|nil err Structured editor or intent failure.
        --@effect Records one active submission without clearing the draft.
        function facade.prepare_submission(intent)
            return line_editor.prepare_submission(intent)
        end

        -- Resolve an exact submission lease, retaining rejected draft bytes.
        --@param submission_generation integer Generation from prepare_submission.
        --@param accepted boolean Whether the domain accepted the submission.
        --@return table|nil snapshot Updated immutable editor facts.
        --@return table|nil err Structured stale, result, or display failure.
        --@effect Clears the lease; accepted submissions clear the draft.
        function facade.resolve_submission(submission_generation, accepted)
            return line_editor.resolve_submission(submission_generation, accepted)
        end

        ---Renders and publishes one increasing semantic block.
        --@param block table Candidate semantic transcript block.
        --@return table|nil receipt Immutable sequence, queue, byte, and rendered facts.
        --@return table|nil err Structured render, ordering, or display failure.
        --@effect Publishes or queues one full block and advances editor_sequence on success.
        function facade.publish(block)
            local rendered, render_error = render_block(block, capabilities, limits)
            if not rendered then return nil, render_error end
            local next_sequence = block.sequence or (editor_sequence + 1)
            if next_sequence <= editor_sequence then
                return nil, failure(
                    "OutOfOrderViewBlock",
                    "line-editor semantic sequence must increase"
                )
            end
            local result, publish_error = line_editor.publish(rendered)
            if not result then return nil, publish_error end
            editor_sequence = next_sequence
            return readonly({
                sequence = next_sequence,
                queued = result.queued,
                bytes = result.bytes,
                rendered = rendered,
            }, "line-editor published block")
        end

        -- Flush queued cooked-mode output at a safe line boundary.
        --@param none Uses the captured terminal editor.
        --@return string|nil bytes Flushed output bytes, possibly empty.
        --@return table|nil err Structured editor or display failure.
        --@effect Writes complete queued blocks and clears the cooked backlog.
        function facade.flush_cooked()
            return line_editor.flush_cooked()
        end

        -- Resume cooked-mode input after its output backlog is empty.
        --@param none Uses the captured terminal editor.
        --@return boolean|nil resumed True after the next prompt is visible.
        --@return table|nil err Structured mode, backlog, or display failure.
        --@effect May write the next cooked prompt.
        function facade.resume_cooked()
            return line_editor.resume_cooked()
        end

        -- Project editor facts together with the semantic block sequence.
        --@param none Uses the captured terminal editor and sequence.
        --@return table snapshot Immutable current editor and sequence facts.
        function facade.snapshot()
            local snapshot = line_editor.snapshot()
            local values = { last_sequence = editor_sequence }
            for key, value in pairs(snapshot) do values[key] = value end
            return readonly(values, "TUI line-editor snapshot")
        end

        -- Close the editor after all queued output and submissions are resolved.
        --@param none Uses the captured terminal editor.
        --@return boolean|nil closed True when editor state is closed.
        --@return table|nil err Structured pending or uncertain-display failure.
        --@effect Closes the underlying editor on success.
        function facade.close()
            return line_editor.close()
        end

        return readonly(facade, "TUI line editor")
    end

    ---Renders independently visible startup fields in their fixed order.
    --@param snapshot table Candidate startup field values.
    --@param visibility table Required independent visibility flags.
    --@param focus string|nil Optional prompt focus appended after visible fields.
    --@return string|nil rendered Complete escaped startup bytes.
    --@return table|nil err Structured shape, value, prompt, or limit failure.
    function service.render_startup(snapshot, visibility, focus)
        local admitted, admitted_visibility_or_error = validate_startup(
            snapshot,
            visibility
        )
        if not admitted then return nil, admitted_visibility_or_error end
        local visible = admitted_visibility_or_error
        local lines = {}
        for _, field in ipairs(STARTUP_FIELDS) do
            if visible[field.id] then
                if field.fixed then
                    lines[#lines + 1] = field.fixed
                else
                    local value = startup_value(field, admitted[field.id])
                    if value == nil then
                        return nil, failure(
                            "InvalidStartupView",
                            "startup field has an invalid value: " .. field.id
                        )
                    end
                    local escaped, escape_error = escape_inline(
                        value,
                        not capabilities.unicode
                    )
                    if not escaped then return nil, escape_error end
                    lines[#lines + 1] = field.label .. ": " .. escaped
                end
            end
        end
        if focus ~= nil then
            local prompt = PROMPTS[focus]
            if not prompt then
                return nil, failure("InvalidPrompt", "startup focus is unknown")
            end
            lines[#lines + 1] = colorize(
                capabilities.ansi and capabilities.color,
                prompt.color,
                prompt.text
            )
        end
        local rendered = #lines == 0 and "" or (table.concat(lines, "\n") .. "\n")
        return check_render_limits(lines, rendered, limits)
    end

    ---Renders one focus prompt and optional exact draft as a complete line.
    --@param focus string Fixed prompt focus identifier.
    --@param draft string|nil Optional untrusted draft bytes to display safely.
    --@return string|nil rendered Complete prompt line with trailing newline.
    --@return table|nil err Structured focus, text, or limit failure.
    function service.render_prompt(focus, draft)
        local prompt = PROMPTS[focus]
        if not prompt then return nil, failure("InvalidPrompt", "prompt focus is unknown") end
        local line = colorize(
            capabilities.ansi and capabilities.color,
            prompt.color,
            prompt.text
        )
        if draft ~= nil then
            local escaped, escape_error = escape_inline(draft, not capabilities.unicode)
            if not escaped then return nil, escape_error end
            line = line .. " " .. escaped
        end
        return check_render_limits({ line }, line .. "\n", limits)
    end

    ---Projects a fixed input intent through the shared CLI action registry.
    --@param intent string Registered input gesture intent.
    --@return table|nil binding Fixed key, availability, action, and text fallback.
    --@return table|nil err Structured unknown-intent failure.
    function service.input_binding(intent)
        local binding = INPUT_BY_INTENT[intent]
        if not binding then
            return nil, failure("InvalidInputIntent", "input intent is not registered")
        end
        return {
            intent = binding.intent,
            key = binding.key,
            key_available = capabilities.keys[binding.key],
            action_id = binding.fallback_action,
            text_fallback = FALLBACK_COMMAND[binding.fallback_action],
        }
    end

    ---Returns current append-only renderer state without transcript retention.
    --@param none Uses the captured renderer state.
    --@return table status Immutable state, sequence, width, and display capability facts.
    function service.status()
        return readonly({
            state = state,
            last_sequence = last_sequence,
            output_unknown = output_unknown,
            width = options.width,
            color_enabled = capabilities.ansi and capabilities.color,
            unicode_enabled = capabilities.unicode,
        }, "TUI renderer status")
    end

    ---Closes the append facade without writing terminal control sequences.
    --@param none Uses the captured renderer state.
    --@return boolean|nil closed True after clean close or if already closed.
    --@return table|nil err BrokenStdout when earlier output remains uncertain.
    --@effect Marks an open renderer closed; does not write terminal bytes.
    function service.close()
        if state == "closed" then return true end
        if state == "faulted" then
            return nil, failure("BrokenStdout", "faulted transcript output remains unknown", {
                output_unknown = true,
            })
        end
        state = "closed"
        return true
    end

    return readonly(service, "TUI renderer")
end

return M
