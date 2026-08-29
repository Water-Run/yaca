--[[
File: ini.lua
Date: 2026-08-29
Author: WaterRun
Description: Parses and writes schema-bound INI while preserving safe concrete syntax.
]]

local text = require("text")

local M = {}

local semantic_values = setmetatable({}, { __mode = "k" })
local document_states = setmetatable({}, { __mode = "k" })

local UTF8_BOM = "\239\187\191"

local function failure(code, message, line, column, reason)
    local result = { code = code, message = message }
    if line ~= nil then result.line = line end
    if column ~= nil then result.column = column end
    if reason ~= nil then result.reason = reason end
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

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function is_dense_array(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then return nil end
    end
    return count
end

local function validate_text_bytes(value)
    if type(value) ~= "string" then
        return nil, failure("InvalidIniValue", "INI text value must be a byte string")
    end
    local carrier, carrier_error = text.text(value)
    if not carrier then return nil, carrier_error end
    return true
end

local function valid_token_bytes(value)
    if type(value) ~= "string" or value == "" then return false end
    for index = 1, #value do
        local byte = value:byte(index)
        local valid = byte >= 0x21 and byte <= 0x7E
            and byte ~= 0x22
            and byte ~= 0x23
            and byte ~= 0x3B
            and byte ~= 0x3D
            and byte ~= 0x5B
            and byte ~= 0x5C
            and byte ~= 0x5D
        if not valid then return false end
    end
    return true
end

local function new_semantic_value(kind, value)
    local wrapper = readonly({ kind = kind, value = value }, "INI " .. kind)
    semantic_values[wrapper] = { kind = kind, value = value }
    return wrapper
end

---Creates an immutable quoted-text INI value.
-- @param value string Strict UTF-8 text; NUL is forbidden.
-- @return table|nil wrapped Typed semantic value.
-- @return table|nil err Structured text failure.
function M.text(value)
    local valid, validation_error = validate_text_bytes(value)
    if not valid then return nil, validation_error end
    return new_semantic_value("text", value)
end

---Creates an immutable unquoted ASCII INI scalar token.
-- @param value string Non-empty token bytes.
-- @return table|nil wrapped Typed semantic value.
-- @return table|nil err Structured token failure.
function M.token(value)
    if not valid_token_bytes(value) then
        return nil, failure("InvalidIniValue", "INI token contains forbidden bytes")
    end
    return new_semantic_value("token", value)
end

---Returns the explicit kind of an INI semantic value.
-- @param value any Candidate wrapper.
-- @return string|nil kind Either text or token.
function M.kind(value)
    local state = semantic_values[value]
    return state and state.kind or nil
end

---Returns the decoded bytes of an INI semantic value.
-- @param value table Candidate wrapper.
-- @return string|nil bytes Exact decoded text or token bytes.
-- @return table|nil err Structured type failure.
function M.value(value)
    local state = semantic_values[value]
    if not state then
        return nil, failure("InvalidIniValue", "value is not an INI semantic wrapper")
    end
    return state.value
end

local function valid_key_name(value)
    return type(value) == "string" and value:match("^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

local function valid_section_fragment(value, allow_trailing_dot)
    if type(value) ~= "string" or value == "" then return false end
    if not allow_trailing_dot and value:sub(-1) == "." then return false end
    if value:match("^[ \t]") or value:match("[ \t]$") then return false end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 0x20
            or byte == 0x5B
            or byte == 0x5D
            or byte == 0x23
            or byte == 0x3B
        then
            return false
        end
    end
    return text.validate_utf8(value)
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidIniSchema", "INI codec options are required")
    end
    local allowed_options = {
        maximum_bytes = true,
        maximum_lines = true,
        maximum_line_bytes = true,
        maximum_value_bytes = true,
        sections = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed_options[key] then
            return nil, failure("InvalidIniSchema", "INI options contain an unknown field")
        end
    end
    local limits = {}
    for _, name in ipairs({
        "maximum_bytes", "maximum_lines", "maximum_line_bytes", "maximum_value_bytes",
    }) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidIniSchema", name .. " must be a positive integer")
        end
        limits[name] = options[name]
    end
    if limits.maximum_line_bytes > limits.maximum_bytes
        or limits.maximum_value_bytes > limits.maximum_bytes
    then
        return nil, failure("InvalidIniSchema", "field limits must not exceed maximum_bytes")
    end

    local section_count = is_dense_array(options.sections)
    if not section_count or section_count == 0 then
        return nil, failure("InvalidIniSchema", "sections must be a non-empty dense array")
    end
    local schema = { sections = {}, exact = {}, families = {} }
    for index, candidate in ipairs(options.sections) do
        if type(candidate) ~= "table" then
            return nil, failure("InvalidIniSchema", "section declarations must be tables")
        end
        local allowed_section = { name = true, prefix = true, fields = true }
        for key in pairs(candidate) do
            if type(key) ~= "string" or not allowed_section[key] then
                return nil, failure("InvalidIniSchema", "section declaration has an unknown field")
            end
        end
        local exact = candidate.name ~= nil
        if exact == (candidate.prefix ~= nil) then
            return nil, failure("InvalidIniSchema", "section requires exactly one name or prefix")
        end
        local selector = exact and candidate.name or candidate.prefix
        if not valid_section_fragment(selector, not exact) then
            return nil, failure("InvalidIniSchema", "section selector is invalid")
        end
        local field_count = is_dense_array(candidate.fields)
        if not field_count or field_count == 0 then
            return nil, failure(
                "InvalidIniSchema",
                "section fields must be a non-empty dense array"
            )
        end
        local declaration = {
            index = index,
            name = candidate.name,
            prefix = candidate.prefix,
            fields = {},
            field_by_key = {},
        }
        for field_index, field in ipairs(candidate.fields) do
            if type(field) ~= "table" then
                return nil, failure("InvalidIniSchema", "field declarations must be tables")
            end
            for key in pairs(field) do
                if key ~= "key" and key ~= "form" then
                    return nil, failure(
                        "InvalidIniSchema",
                        "field declaration has an unknown field"
                    )
                end
            end
            if not valid_key_name(field.key)
                or (field.form ~= "text" and field.form ~= "token" and field.form ~= "either")
                or declaration.field_by_key[field.key]
            then
                return nil, failure(
                    "InvalidIniSchema",
                    "field declaration is invalid or duplicated"
                )
            end
            local admitted = { key = field.key, form = field.form, index = field_index }
            declaration.fields[field_index] = admitted
            declaration.field_by_key[field.key] = admitted
        end
        if exact then
            if schema.exact[selector] then
                return nil, failure("InvalidIniSchema", "exact section is duplicated")
            end
            schema.exact[selector] = declaration
        else
            for _, previous in ipairs(schema.families) do
                if selector:sub(1, #previous.prefix) == previous.prefix
                    or previous.prefix:sub(1, #selector) == selector
                then
                    return nil, failure("InvalidIniSchema", "section family prefixes overlap")
                end
            end
            schema.families[#schema.families + 1] = declaration
        end
        schema.sections[index] = declaration
    end
    for name in pairs(schema.exact) do
        for _, family in ipairs(schema.families) do
            if name:sub(1, #family.prefix) == family.prefix then
                return nil, failure("InvalidIniSchema", "exact and family sections overlap")
            end
        end
    end
    return { limits = limits, schema = schema }
end

local function match_section(schema, name)
    local exact = schema.exact[name]
    if exact then return exact end
    for _, family in ipairs(schema.families) do
        if name:sub(1, #family.prefix) == family.prefix
            and #name > #family.prefix
        then
            return family
        end
    end
    return nil
end

local function syntax_failure(reason, line, column)
    return failure("IniSyntax", "INI input is invalid", line, column, reason)
end

local function limit_failure(reason, line, column)
    return failure("IniLimit", "INI input exceeds an injected limit", line, column, reason)
end

local function trim_bounds(value, first, last)
    while first <= last do
        local byte = value:byte(first)
        if byte == 0x20 or byte == 0x09 then first = first + 1 else break end
    end
    while last >= first do
        local byte = value:byte(last)
        if byte == 0x20 or byte == 0x09 then last = last - 1 else break end
    end
    return first, last
end

local function split_lines(source, body_start, limits)
    local lines = {}
    local index = body_start
    local line_number = 0
    while index <= #source do
        line_number = line_number + 1
        if line_number > limits.maximum_lines then
            return nil, limit_failure("lines", line_number, 1)
        end
        local newline = source:find("\n", index, true)
        local finish = newline and newline - 1 or #source
        local ending = ""
        if newline then
            if finish >= index and source:byte(finish) == 0x0D then
                finish = finish - 1
                ending = "\r\n"
            else
                ending = "\n"
            end
        end
        local content = source:sub(index, finish)
        local bare_cr = content:find("\r", 1, true)
        if bare_cr then return nil, syntax_failure("line-ending", line_number, bare_cr) end
        if #content > limits.maximum_line_bytes then
            return nil, limit_failure("line-bytes", line_number, 1)
        end
        lines[#lines + 1] = {
            content = content,
            ending = ending,
            line = line_number,
            offset = index,
        }
        if not newline then break end
        index = newline + 1
    end
    return lines
end

local function first_nonspace(content)
    local index = 1
    while content:byte(index) == 0x20 or content:byte(index) == 0x09 do
        index = index + 1
    end
    return index
end

local function parse_quoted(content, start_index, line, maximum_value_bytes)
    local parts = {}
    local decoded_bytes = 0
    local index = start_index + 1
    local segment_start = index
    while index <= #content do
        local byte = content:byte(index)
        if byte == 0x22 or byte == 0x5C or byte < 0x20 then
            if index > segment_start then
                local segment = content:sub(segment_start, index - 1)
                decoded_bytes = decoded_bytes + #segment
                if decoded_bytes > maximum_value_bytes then
                    return nil, limit_failure("value-bytes", line, start_index)
                end
                parts[#parts + 1] = segment
            end
            if byte == 0x22 then
                return new_semantic_value("text", table.concat(parts)), index
            end
            if byte < 0x20 then
                return nil, syntax_failure("quoted-control", line, index)
            end
            local escaped = content:byte(index + 1)
            local decoded
            if escaped == 0x5C then decoded = "\\"
            elseif escaped == 0x22 then decoded = "\""
            elseif escaped == 0x6E then decoded = "\n"
            elseif escaped == 0x72 then decoded = "\r"
            elseif escaped == 0x74 then decoded = "\t"
            else return nil, syntax_failure("unknown-escape", line, index) end
            decoded_bytes = decoded_bytes + 1
            if decoded_bytes > maximum_value_bytes then
                return nil, limit_failure("value-bytes", line, start_index)
            end
            parts[#parts + 1] = decoded
            index = index + 2
            segment_start = index
        else
            index = index + 1
        end
    end
    return nil, syntax_failure("unterminated-quote", line, start_index)
end

local function comment_or_end(content, index, line)
    while content:byte(index) == 0x20 or content:byte(index) == 0x09 do
        index = index + 1
    end
    local byte = content:byte(index)
    if byte == nil or byte == 0x23 or byte == 0x3B then return true end
    return nil, syntax_failure("trailing-data", line, index)
end

local function parse_assignment(record, current_section, limits)
    local content = record.content
    local start_index = first_nonspace(content)
    local equals = content:find("=", start_index, true)
    if not equals then return nil, syntax_failure("assignment", record.line, start_index) end
    local key_first, key_last = trim_bounds(content, start_index, equals - 1)
    local key = content:sub(key_first, key_last)
    if not valid_key_name(key) then
        return nil, syntax_failure("key", record.line, key_first)
    end
    local field = current_section.declaration.field_by_key[key]
    if not field then
        return nil, syntax_failure("unknown-key", record.line, key_first)
    end
    if current_section.values[key] then
        return nil, syntax_failure("duplicate-key", record.line, key_first)
    end
    local value_start = equals + 1
    while content:byte(value_start) == 0x20 or content:byte(value_start) == 0x09 do
        value_start = value_start + 1
    end
    local wrapped, value_finish
    if content:byte(value_start) == 0x22 then
        local parse_error
        wrapped, value_finish = parse_quoted(
            content,
            value_start,
            record.line,
            limits.maximum_value_bytes
        )
        if not wrapped then return nil, value_finish end
        local trailing, trailing_error = comment_or_end(content, value_finish + 1, record.line)
        if not trailing then return nil, trailing_error end
    else
        value_finish = value_start
        while true do
            local byte = content:byte(value_finish)
            if byte == nil or byte == 0x20 or byte == 0x09 or byte == 0x23 or byte == 0x3B then
                break
            end
            value_finish = value_finish + 1
        end
        local token = content:sub(value_start, value_finish - 1)
        if #token > limits.maximum_value_bytes then
            return nil, limit_failure("value-bytes", record.line, value_start)
        end
        if not valid_token_bytes(token) then
            return nil, syntax_failure("token", record.line, value_start)
        end
        wrapped = new_semantic_value("token", token)
        value_finish = value_finish - 1
        local trailing, trailing_error = comment_or_end(content, value_finish + 1, record.line)
        if not trailing then return nil, trailing_error end
    end
    local kind = semantic_values[wrapped].kind
    if field.form ~= "either" and field.form ~= kind then
        return nil, syntax_failure("value-form", record.line, value_start)
    end
    current_section.values[key] = wrapped
    record.kind = "assignment"
    record.section = current_section.name
    record.key = key
    record.prefix = content:sub(1, value_start - 1)
    record.suffix = content:sub(value_finish + 1)
    return true
end

local function parse_section(record, schema)
    local content = record.content
    local start_index = first_nonspace(content)
    local close = content:find("]", start_index + 1, true)
    if not close then return nil, syntax_failure("section", record.line, start_index) end
    local name_first, name_last = trim_bounds(content, start_index + 1, close - 1)
    local name = content:sub(name_first, name_last)
    if not valid_section_fragment(name, true) then
        return nil, syntax_failure("section-name", record.line, name_first)
    end
    local trailing, trailing_error = comment_or_end(content, close + 1, record.line)
    if not trailing then return nil, trailing_error end
    local declaration = match_section(schema, name)
    if not declaration then
        return nil, syntax_failure("unknown-section", record.line, name_first)
    end
    record.kind = "section"
    record.section = name
    return { name = name, declaration = declaration }
end

local function new_document(state)
    local document = readonly({}, "INI document")
    document_states[document] = state
    return document
end

local function parse_source(source, admitted)
    local limits, schema = admitted.limits, admitted.schema
    if type(source) ~= "string" then
        return nil, failure("InvalidIniType", "INI source must be a byte string")
    end
    if #source > limits.maximum_bytes then return nil, limit_failure("bytes", 1, 1) end
    local valid, validation = text.validate_utf8(source)
    if not valid then return nil, validation end
    if validation.contains_nul then
        return nil, syntax_failure("nul", 1, 1)
    end
    local has_bom = source:sub(1, 3) == UTF8_BOM
    local body_start = has_bom and 4 or 1
    if source:sub(body_start, body_start + 2) == UTF8_BOM then
        return nil, syntax_failure("bom", 1, 1)
    end
    local physical, split_error = split_lines(source, body_start, limits)
    if not physical then return nil, split_error end
    local state = {
        owner = admitted.owner,
        sections = {},
        section_by_name = {},
        physical = physical,
        source = source,
        has_bom = has_bom,
        concrete_safe = true,
        dirty = {},
    }
    local current
    for _, record in ipairs(physical) do
        local start_index = first_nonspace(record.content)
        local first = record.content:byte(start_index)
        if first == nil or first == 0x23 or first == 0x3B then
            record.kind = first and "comment" or "blank"
        elseif first == 0x5B then
            local selected, section_error = parse_section(record, schema)
            if not selected then return nil, section_error end
            current = state.section_by_name[selected.name]
            if not current then
                current = {
                    name = selected.name,
                    declaration = selected.declaration,
                    values = {},
                    order = #state.sections + 1,
                }
                state.sections[#state.sections + 1] = current
                state.section_by_name[selected.name] = current
            end
        else
            if not current then
                return nil, syntax_failure("assignment-before-section", record.line, start_index)
            end
            local assigned, assignment_error = parse_assignment(record, current, limits)
            if not assigned then return nil, assignment_error end
        end
    end
    return new_document(state)
end

local function validate_wrapper(field, wrapped, limits)
    local value = semantic_values[wrapped]
    if not value then
        return nil, failure("InvalidIniValue", "document fields require typed INI values")
    end
    if field.form ~= "either" and field.form ~= value.kind then
        return nil, failure("InvalidIniValue", "INI value form does not match its field")
    end
    if #value.value > limits.maximum_value_bytes then
        return nil, limit_failure("value-bytes")
    end
    return true
end

local function clone_state(state)
    local result = {
        owner = state.owner,
        sections = {},
        section_by_name = {},
        physical = state.physical,
        source = state.source,
        has_bom = state.has_bom,
        concrete_safe = state.concrete_safe,
        dirty = {},
    }
    for key, value in pairs(state.dirty) do result.dirty[key] = value end
    for index, section in ipairs(state.sections) do
        local copied = {
            name = section.name,
            declaration = section.declaration,
            values = {},
            order = index,
        }
        for key, value in pairs(section.values) do copied.values[key] = value end
        result.sections[index] = copied
        result.section_by_name[copied.name] = copied
    end
    return result
end

local function build_document(section_inputs, admitted)
    local section_count = is_dense_array(section_inputs)
    if section_count == nil then
        return nil, failure("InvalidIniDocument", "sections must be a dense array")
    end
    local state = {
        owner = admitted.owner,
        sections = {},
        section_by_name = {},
        concrete_safe = false,
        dirty = {},
    }
    for index, input in ipairs(section_inputs) do
        if type(input) ~= "table"
            or type(input.name) ~= "string"
            or type(input.values) ~= "table"
        then
            return nil, failure("InvalidIniDocument", "section input requires name and values")
        end
        for key in pairs(input) do
            if key ~= "name" and key ~= "values" then
                return nil, failure("InvalidIniDocument", "section input has an unknown field")
            end
        end
        if state.section_by_name[input.name] then
            return nil, failure("InvalidIniDocument", "document section is duplicated")
        end
        local declaration = match_section(admitted.schema, input.name)
        if not declaration then
            return nil, failure("InvalidIniDocument", "document contains an unknown section")
        end
        local section = {
            name = input.name,
            declaration = declaration,
            values = {},
            order = index,
        }
        for key, wrapped in pairs(input.values) do
            local field = declaration.field_by_key[key]
            if not field then
                return nil, failure("InvalidIniDocument", "document contains an unknown key")
            end
            local valid, value_error = validate_wrapper(field, wrapped, admitted.limits)
            if not valid then return nil, value_error end
            section.values[key] = wrapped
        end
        state.sections[index] = section
        state.section_by_name[section.name] = section
    end
    return new_document(state)
end

local function edit_document(document, changes, admitted)
    local state = document_states[document]
    if not state or state.owner ~= admitted.owner then
        return nil, failure("InvalidIniDocument", "document belongs to another INI codec")
    end
    local change_count = is_dense_array(changes)
    if not change_count then
        return nil, failure("InvalidIniEdit", "changes must be a dense array")
    end
    local result = clone_state(state)
    local seen = {}
    for _, change in ipairs(changes) do
        if type(change) ~= "table"
            or type(change.section) ~= "string"
            or not valid_key_name(change.key)
        then
            return nil, failure("InvalidIniEdit", "change requires section, key, and value")
        end
        for key in pairs(change) do
            if key ~= "section" and key ~= "key" and key ~= "value" then
                return nil, failure("InvalidIniEdit", "change contains an unknown field")
            end
        end
        local identity = change.section .. "\0" .. change.key
        if seen[identity] then return nil, failure("InvalidIniEdit", "change is duplicated") end
        seen[identity] = true
        local declaration = match_section(admitted.schema, change.section)
        local field = declaration and declaration.field_by_key[change.key]
        if not field then
            return nil, failure("InvalidIniEdit", "change targets an unknown field")
        end
        local valid, value_error = validate_wrapper(field, change.value, admitted.limits)
        if not valid then return nil, value_error end
        local section = result.section_by_name[change.section]
        if not section then
            section = {
                name = change.section,
                declaration = declaration,
                values = {},
                order = #result.sections + 1,
            }
            result.sections[#result.sections + 1] = section
            result.section_by_name[section.name] = section
            result.concrete_safe = false
        elseif section.values[change.key] == nil then
            result.concrete_safe = false
        end
        local old = section.values[change.key] and semantic_values[section.values[change.key]]
        local replacement = semantic_values[change.value]
        section.values[change.key] = change.value
        if not old or old.kind ~= replacement.kind or old.value ~= replacement.value then
            result.dirty[identity] = true
        end
    end
    return new_document(result)
end

local function encode_value(wrapped)
    local state = assert(semantic_values[wrapped])
    if state.kind == "token" then return state.value end
    local output = { "\"" }
    local segment_start = 1
    for index = 1, #state.value do
        local byte = state.value:byte(index)
        local replacement
        if byte == 0x5C then replacement = "\\\\"
        elseif byte == 0x22 then replacement = "\\\""
        elseif byte == 0x0A then replacement = "\\n"
        elseif byte == 0x0D then replacement = "\\r"
        elseif byte == 0x09 then replacement = "\\t"
        end
        if replacement then
            if index > segment_start then
                output[#output + 1] = state.value:sub(segment_start, index - 1)
            end
            output[#output + 1] = replacement
            segment_start = index + 1
        end
    end
    if segment_start <= #state.value then output[#output + 1] = state.value:sub(segment_start) end
    output[#output + 1] = "\""
    return table.concat(output)
end

local function append_bounded(writer, bytes, limits, line_bytes)
    if line_bytes and line_bytes > limits.maximum_line_bytes then
        return nil, limit_failure("line-bytes")
    end
    if writer.bytes > limits.maximum_bytes - #bytes then
        return nil, limit_failure("bytes")
    end
    writer.bytes = writer.bytes + #bytes
    writer.parts[#writer.parts + 1] = bytes
    return true
end

local function ordered_sections(state, schema)
    local buckets = {}
    for index = 1, #schema.sections do buckets[index] = {} end
    for _, section in ipairs(state.sections) do
        local bucket = buckets[section.declaration.index]
        bucket[#bucket + 1] = section
    end
    local result = {}
    for _, bucket in ipairs(buckets) do
        table.sort(bucket, function(left, right) return left.order < right.order end)
        for _, section in ipairs(bucket) do result[#result + 1] = section end
    end
    return result
end

local function write_canonical(state, admitted)
    local writer = { parts = {}, bytes = 0, lines = 0 }
    local sections = ordered_sections(state, admitted.schema)
    for section_index, section in ipairs(sections) do
        if section_index > 1 then
            writer.lines = writer.lines + 1
            if writer.lines > admitted.limits.maximum_lines then
                return nil, limit_failure("lines")
            end
            local ok, append_error = append_bounded(writer, "\n", admitted.limits, 0)
            if not ok then return nil, append_error end
        end
        local header = "[" .. section.name .. "]\n"
        writer.lines = writer.lines + 1
        if writer.lines > admitted.limits.maximum_lines then return nil, limit_failure("lines") end
        local ok, append_error = append_bounded(
            writer,
            header,
            admitted.limits,
            #header - 1
        )
        if not ok then return nil, append_error end
        for _, field in ipairs(section.declaration.fields) do
            local wrapped = section.values[field.key]
            if wrapped then
                local line = field.key .. " = " .. encode_value(wrapped) .. "\n"
                writer.lines = writer.lines + 1
                if writer.lines > admitted.limits.maximum_lines then
                    return nil, limit_failure("lines")
                end
                ok, append_error = append_bounded(
                    writer,
                    line,
                    admitted.limits,
                    #line - 1
                )
                if not ok then return nil, append_error end
            end
        end
    end
    return table.concat(writer.parts), readonly({ mode = "canonical" }, "INI write metadata")
end

local function write_concrete(state, admitted)
    if not state.concrete_safe or not state.physical then return nil end
    local writer = { parts = {}, bytes = 0 }
    if state.has_bom then
        local ok, append_error = append_bounded(writer, UTF8_BOM, admitted.limits)
        if not ok then return false, append_error end
    end
    for _, record in ipairs(state.physical) do
        local content = record.content
        if record.kind == "assignment"
            and state.dirty[record.section .. "\0" .. record.key]
        then
            local section = assert(state.section_by_name[record.section])
            content = record.prefix .. encode_value(section.values[record.key]) .. record.suffix
        end
        if #content > admitted.limits.maximum_line_bytes then
            return false, limit_failure("line-bytes", record.line, 1)
        end
        local ok, append_error = append_bounded(
            writer,
            content .. record.ending,
            admitted.limits
        )
        if not ok then return false, append_error end
    end
    return table.concat(writer.parts), readonly({
        mode = "concrete-preserved",
    }, "INI write metadata")
end

---Creates a bounded, schema-bound INI codec.
-- The schema owns the only accepted sections, fields, value forms, and their
-- canonical order. All numeric or enum interpretation remains with config.lua.
-- @param options table Required limits and ordered section declarations.
-- @return table|nil codec Immutable INI service.
-- @return table|nil err Structured schema failure.
function M.new(options)
    local admitted, options_error = validate_options(options)
    if not admitted then return nil, options_error end
    admitted.owner = {}
    local service = {}

    ---Parses one complete INI generation and rejects unknown or duplicate fields.
    -- @param source string Exact INI bytes with an optional single UTF-8 BOM.
    -- @return table|nil document Immutable semantic/concrete document handle.
    -- @return table|nil err Structured syntax, schema, UTF-8, or limit failure.
    function service.parse(source)
        return parse_source(source, admitted)
    end

    ---Builds an INI document from ordered semantic sections.
    -- @param sections table Dense array of name/values section records.
    -- @return table|nil document Immutable document handle.
    -- @return table|nil err Structured shape, schema, or value failure.
    function service.build(sections)
        return build_document(sections, admitted)
    end

    ---Returns section names in their admitted physical or construction order.
    -- @param document table Document returned by this codec.
    -- @return table|nil names Dense copied name array.
    -- @return table|nil err Structured document failure.
    function service.sections(document)
        local state = document_states[document]
        if not state or state.owner ~= admitted.owner then
            return nil, failure("InvalidIniDocument", "document belongs to another INI codec")
        end
        local result = {}
        for index, section in ipairs(state.sections) do result[index] = section.name end
        return result
    end

    ---Looks up a typed semantic field without inventing a missing value.
    -- @param document table Document returned by this codec.
    -- @param section string Exact admitted section name.
    -- @param key string Exact admitted field name.
    -- @return table|nil value Typed INI value, or nil when absent.
    -- @return table|nil err Structured document or selector failure.
    function service.get(document, section, key)
        local state = document_states[document]
        if not state or state.owner ~= admitted.owner then
            return nil, failure("InvalidIniDocument", "document belongs to another INI codec")
        end
        if type(section) ~= "string" or type(key) ~= "string" then
            return nil, failure("InvalidIniSelector", "section and key must be strings")
        end
        local selected = state.section_by_name[section]
        return selected and selected.values[key] or nil
    end

    ---Returns a new document with a validated set of semantic field changes.
    -- Existing-field edits retain enough source structure for concrete writing.
    -- Structural additions are valid but deliberately force canonical output.
    -- @param document table Source document.
    -- @param changes table Dense section/key/value change records.
    -- @return table|nil edited New immutable document handle.
    -- @return table|nil err Structured edit failure.
    function service.edit(document, changes)
        return edit_document(document, changes, admitted)
    end

    ---Writes semantic canonical INI or preserves safe source syntax on request.
    -- @param document table Document returned by this codec.
    -- @param write_options table|nil Supports preserve_concrete=true only.
    -- @return string|nil source Complete INI bytes.
    -- @return table|nil metadata_or_err Write mode metadata or structured failure.
    function service.write(document, write_options)
        local state = document_states[document]
        if not state or state.owner ~= admitted.owner then
            return nil, failure("InvalidIniDocument", "document belongs to another INI codec")
        end
        write_options = write_options or {}
        if type(write_options) ~= "table" then
            return nil, failure("InvalidIniWriteOptions", "write options must be a table")
        end
        for key in pairs(write_options) do
            if key ~= "preserve_concrete" then
                return nil, failure(
                    "InvalidIniWriteOptions",
                    "write options contain an unknown field"
                )
            end
        end
        if write_options.preserve_concrete ~= nil
            and type(write_options.preserve_concrete) ~= "boolean"
        then
            return nil, failure("InvalidIniWriteOptions", "preserve_concrete must be boolean")
        end
        if write_options.preserve_concrete then
            local concrete, metadata_or_error = write_concrete(state, admitted)
            if concrete == false then return nil, metadata_or_error end
            if concrete ~= nil then return concrete, metadata_or_error end
        end
        return write_canonical(state, admitted)
    end

    service.limits = readonly({
        maximum_bytes = admitted.limits.maximum_bytes,
        maximum_lines = admitted.limits.maximum_lines,
        maximum_line_bytes = admitted.limits.maximum_line_bytes,
        maximum_value_bytes = admitted.limits.maximum_value_bytes,
    }, "INI limits")

    return readonly(service, "INI codec")
end

return M
