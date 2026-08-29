--[[
File: ini_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies strict schema-bound INI parsing and safe concrete writing.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = { require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local ini = load_module("ini")
local fixtures = load_table(".develope-docs/contracts/fixtures/config.lua")

local function options(overrides)
    local result = {
        maximum_bytes = 8192,
        maximum_lines = 128,
        maximum_line_bytes = 1024,
        maximum_value_bytes = 512,
        sections = {
            {
                name = "General",
                fields = {
                    { key = "SchemaVersion", form = "token" },
                    { key = "SystemPrompt", form = "text" },
                    { key = "LogLevel", form = "token" },
                },
            },
            {
                name = "Text",
                fields = { { key = "Value", form = "text" } },
            },
            {
                prefix = "Permission.",
                fields = {
                    { key = "Description", form = "text" },
                    { key = "Read", form = "token" },
                    { key = "Write", form = "token" },
                },
            },
            {
                prefix = "Model.",
                fields = {
                    { key = "Enabled", form = "token" },
                    { key = "Protocol", form = "token" },
                    { key = "Endpoint", form = "text" },
                    { key = "RemoteModel", form = "text" },
                    { key = "Key", form = "text" },
                },
            },
        },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function codec(overrides)
    return assert(ini.new(options(overrides)))
end

local function decoded(service, document, section, key)
    return assert(ini.value(assert(service.get(document, section, key))))
end

return {
    name = "unit/ini",
    cases = {
        {
            name = "config string fixtures have one exact quoted grammar",
            run = function()
                local service = codec()
                for _, case in ipairs(fixtures.string_vectors) do
                    local source = "[Text]\nValue = " .. case.encoded .. "\n"
                    local document, parse_error = service.parse(source)
                    if case.valid then
                        A.truthy(document, case.id)
                        local wrapped = assert(service.get(document, "Text", "Value"))
                        A.equal(ini.kind(wrapped), "text")
                        A.equal(assert(ini.value(wrapped)), case.decoded)
                    else
                        A.falsy(document, case.id)
                        A.equal(parse_error.code, "IniSyntax")
                    end
                end
            end,
        },
        {
            name = "comments stay outside quotes and scalar forms remain explicit",
            run = function()
                local service = codec()
                local source = table.concat({
                    "; leading comment",
                    "[General] # section comment",
                    "SchemaVersion = 0.1.0 ; scalar",
                    "SystemPrompt = \"# keep ; both\" # comment",
                    "LogLevel = debug",
                    "",
                }, "\n")
                local document = assert(service.parse(source))
                A.equal(decoded(service, document, "General", "SchemaVersion"), "0.1.0")
                A.equal(decoded(service, document, "General", "SystemPrompt"), "# keep ; both")
                A.equal(ini.kind(service.get(document, "General", "LogLevel")), "token")
                A.deep_equal(assert(service.sections(document)), { "General" })
                A.falsy(service.get(document, "General", "Missing"))
            end,
        },
        {
            name = "repeated sections merge only while every key stays unique",
            run = function()
                local service = codec()
                local merged = assert(service.parse(table.concat({
                    "[General]",
                    "SchemaVersion = 0.1.0",
                    "[General]",
                    "SystemPrompt = \"ok\"",
                }, "\n")))
                A.deep_equal(assert(service.sections(merged)), { "General" })
                A.equal(decoded(service, merged, "General", "SystemPrompt"), "ok")

                local duplicate, duplicate_error = service.parse(table.concat({
                    "[General]",
                    "LogLevel = info",
                    "[General]",
                    "LogLevel = debug",
                }, "\n"))
                A.falsy(duplicate)
                A.equal(duplicate_error.reason, "duplicate-key")
                A.equal(duplicate_error.line, 4)
            end,
        },
        {
            name = "unknown sections keys and case variants fail closed",
            run = function()
                local service = codec()
                local cases = {
                    { "[Unknown]\nValue = \"x\"", "unknown-section" },
                    { "[General]\nUnknown = value", "unknown-key" },
                    { "[general]\nLogLevel = info", "unknown-section" },
                    { "LogLevel = info", "assignment-before-section" },
                    { "[Permission.]\nRead = allow", "unknown-section" },
                    { "[General]\nLogLevel = \"info\"", "value-form" },
                    { "[General]\nSystemPrompt = raw", "value-form" },
                }
                for _, case in ipairs(cases) do
                    local document, parse_error = service.parse(case[1])
                    A.falsy(document)
                    A.equal(parse_error.reason, case[2])
                end
            end,
        },
        {
            name = "reader accepts one BOM and LF or CRLF but rejects unsafe syntax",
            run = function()
                local service = codec()
                local accepted = "\239\187\191[General]\r\nLogLevel = info\r\n"
                A.truthy(service.parse(accepted))
                local cases = {
                    { "\239\187\191\239\187\191[General]\n", "bom" },
                    { "[General]\rLogLevel = info", "line-ending" },
                    { "[Text]\nValue = \"bad\\q\"", "unknown-escape" },
                    { "[Text]\nValue = \"\"\"block\"\"\"", "trailing-data" },
                    { "[Text]\nValue = \"bad\nline\"", "unterminated-quote" },
                    { "[General]\nLogLevel = info\\", "token" },
                    { "[General]\nLogLevel = in fo", "trailing-data" },
                    { "[General]\nLogLevel = in\0fo", "nul" },
                }
                for _, case in ipairs(cases) do
                    local document, parse_error = service.parse(case[1])
                    A.falsy(document)
                    A.equal(parse_error.reason, case[2])
                end
            end,
        },
        {
            name = "semantic writer follows schema field and family order",
            run = function()
                local service = codec()
                local document = assert(service.build({
                    {
                        name = "Model.Zed",
                        values = {
                            RemoteModel = assert(ini.text("remote")),
                            Enabled = assert(ini.token("true")),
                        },
                    },
                    {
                        name = "Permission.Second",
                        values = { Write = assert(ini.token("deny")) },
                    },
                    {
                        name = "General",
                        values = {
                            LogLevel = assert(ini.token("debug")),
                            SchemaVersion = assert(ini.token("0.1.0")),
                            SystemPrompt = assert(ini.text("a\n\"b\\c\t")),
                        },
                    },
                    {
                        name = "Permission.First",
                        values = { Read = assert(ini.token("allow")) },
                    },
                }))
                local output, metadata = assert(service.write(document))
                A.equal(metadata.mode, "canonical")
                A.equal(output, table.concat({
                    "[General]",
                    "SchemaVersion = 0.1.0",
                    "SystemPrompt = \"a\\n\\\"b\\\\c\\t\"",
                    "LogLevel = debug",
                    "",
                    "[Permission.Second]",
                    "Write = deny",
                    "",
                    "[Permission.First]",
                    "Read = allow",
                    "",
                    "[Model.Zed]",
                    "Enabled = true",
                    "RemoteModel = \"remote\"",
                    "",
                }, "\n"))
            end,
        },
        {
            name = "safe edits preserve untouched bytes comments BOM and line endings",
            run = function()
                local service = codec()
                local source = table.concat({
                    "\239\187\191; heading\r",
                    "[General] ; group\r",
                    "LogLevel=debug # unchanged\r",
                    "SystemPrompt   =   \"old\"   ; retained\r",
                    "SchemaVersion = 0.1.0\r",
                    "",
                }, "\n")
                local document = assert(service.parse(source))
                local edited = assert(service.edit(document, {
                    {
                        section = "General",
                        key = "SystemPrompt",
                        value = assert(ini.text("new\n\"value\"")),
                    },
                }))
                local output, metadata = service.write(edited, { preserve_concrete = true })
                A.equal(metadata.mode, "concrete-preserved")
                A.equal(output, source:gsub(
                    "\"old\"",
                    "\"new\\n\\\"value\\\"\"",
                    1
                ))
                A.equal(decoded(service, document, "General", "SystemPrompt"), "old")
                A.equal(decoded(service, edited, "General", "SystemPrompt"), "new\n\"value\"")
            end,
        },
        {
            name = "structural edits deliberately fall back to canonical output",
            run = function()
                local service = codec()
                local document = assert(service.parse("[General]\nLogLevel = info\n"))
                local edited = assert(service.edit(document, {
                    {
                        section = "General",
                        key = "SystemPrompt",
                        value = assert(ini.text("added")),
                    },
                }))
                local output, metadata = service.write(edited, { preserve_concrete = true })
                A.equal(metadata.mode, "canonical")
                A.contains(output, "SystemPrompt = \"added\"")
                A.contains(output, "LogLevel = info")
            end,
        },
        {
            name = "limits schemas wrappers and document handles reject ambiguity",
            run = function()
                local byte_codec = codec({
                    maximum_bytes = 24,
                    maximum_line_bytes = 24,
                    maximum_value_bytes = 24,
                })
                local document, parse_error = byte_codec.parse(
                    "[General]\nLogLevel = debug\n"
                )
                A.falsy(document)
                A.equal(parse_error.reason, "bytes")

                local line_codec = codec({ maximum_line_bytes = 8, maximum_value_bytes = 8 })
                local long_line, line_error = line_codec.parse("[General]\n")
                A.falsy(long_line)
                A.equal(line_error.reason, "line-bytes")

                local service = codec({ maximum_value_bytes = 4 })
                local long_value, value_error = service.parse("[Text]\nValue = \"abcde\"")
                A.falsy(long_value)
                A.equal(value_error.reason, "value-bytes")
                A.falsy(ini.token("has space"))
                A.falsy(ini.text("nul\0text"))
                A.raises(function() service.limits.maximum_bytes = 1 end, "cannot be modified")
                local valid_document = assert(service.parse("[Text]\nValue = \"ok\""))
                A.raises(function() valid_document.extra = true end, "cannot be modified")

                local other_service = codec({ maximum_value_bytes = 4 })
                local foreign, foreign_error = other_service.write(valid_document)
                A.falsy(foreign)
                A.equal(foreign_error.code, "InvalidIniDocument")

                local invalid_schema, schema_error = ini.new(options({ surprise = true }))
                A.falsy(invalid_schema)
                A.equal(schema_error.code, "InvalidIniSchema")
            end,
        },
    },
}
