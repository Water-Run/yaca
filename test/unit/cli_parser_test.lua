--[[
File: cli_parser_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies registry-generated argv, line, help, machine, and exit projections.
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

local function read_file(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local source = handle:read("a")
    handle:close()
    return source
end

local cache = {}
local cli = load_module("cli", cache)
local json = load_module("json", cache)
local contract = load_table(".develope-docs/contracts/actions.lua")
local diagnostics = load_table(".develope-docs/contracts/diagnostics.lua")
local fixtures = load_table(".develope-docs/contracts/fixtures/argv.lua")

local function json_codec()
    return assert(json.new({
        maximum_bytes = 65536,
        maximum_depth = 16,
        maximum_nodes = 2048,
        maximum_string_bytes = 16384,
        maximum_number_bytes = 64,
    }))
end

local function new_service(platform, machine)
    return assert(cli.new({
        platform = platform or "linux",
        json_codec = machine and json_codec() or nil,
    }))
end

local function assert_subset(expected, actual, path)
    path = path or "value"
    if type(expected) ~= "table" then
        A.equal(actual, expected, path)
        return
    end
    A.type(actual, "table", path)
    for key, value in pairs(expected) do
        assert_subset(value, actual[key], path .. "." .. tostring(key))
    end
end

local function parse_fixture(case)
    local platform = case.platform == "windows" and "windows" or "linux"
    local service = new_service(platform)
    if case.argv then return service.parse_argv(case.argv, { tty = case.tty }) end
    if case.platform == "chat" then
        return service.parse_chat(case.line, { tty = case.tty })
    end
    return service.parse_context_repl(case.line, { tty = case.tty })
end

local function assert_parse_error(service, method, source, expected, facts)
    local result, parse_error = service[method](source, facts)
    A.falsy(result)
    A.equal(parse_error.code, expected)
    return parse_error
end

local function without_final_newline(value)
    return (value:gsub("\n$", ""))
end

return {
    name = "unit/cli-parser",
    cases = {
        {
            name = "runtime registry is an exact enriched projection of all 39 actions",
            run = function()
                local registry = cli.registry()
                A.equal(registry.contract_version, contract.contract_version)
                A.equal(#registry.actions, 39)
                assert_subset(contract.parser, registry.parser, "parser")
                assert_subset(contract.exit_classes, registry.exit_classes, "exit_classes")
                assert_subset(contract.machine_output, registry.machine_output, "machine_output")
                assert_subset(contract.fd_mode_matrix, registry.fd_mode_matrix, "fd_mode_matrix")
                for index, descriptor in ipairs(contract.actions) do
                    assert_subset(descriptor, registry.actions[index], descriptor.id)
                end

                local ids, long, short, slash = {}, {}, {}, {}
                for _, descriptor in ipairs(registry.actions) do
                    A.falsy(ids[descriptor.id], descriptor.id)
                    ids[descriptor.id] = true
                    A.type(descriptor.summary, "string")
                    for _, projection in ipairs(descriptor.projections) do
                        if projection.kind == "argv" and projection.long then
                            A.falsy(long[projection.long], projection.long)
                            A.falsy(short[projection.short], projection.short)
                            A.falsy(slash[projection.slash], projection.slash)
                            long[projection.long] = descriptor.id
                            short[projection.short] = descriptor.id
                            slash[projection.slash] = descriptor.id
                        end
                    end
                end
                A.falsy(short["-dc"])
                A.falsy(short["-rc"])

                registry.actions[1].id = "changed"
                A.equal(cli.registry().actions[1].id, "run-chat")
                local service = new_service()
                local descriptor = assert(service.action("run-chat"))
                descriptor.id = "changed-again"
                A.equal(assert(service.action("run-chat")).id, "run-chat")
                A.raises(function() service.extra = true end, "cannot be modified")
            end,
        },
        {
            name = "frozen argv chat and Context fixtures normalize or fail exactly",
            run = function()
                for _, case in ipairs(fixtures.cases) do
                    local request, parse_error = parse_fixture(case)
                    if case.expected_action then
                        A.truthy(request, case.id .. ": " .. tostring(parse_error and parse_error.code))
                        A.equal(request.id, case.expected_action, case.id)
                        for key, value in pairs(case.normalized or {}) do
                            A.deep_equal(request[key], value, case.id .. "." .. key)
                        end
                    else
                        A.falsy(request, case.id)
                        A.equal(parse_error.code, case.expected_error, case.id)
                    end
                end
            end,
        },
        {
            name = "all top aliases select one action and end-of-options preserves paths",
            run = function()
                local linux = new_service("linux")
                local windows = new_service("windows")
                local suffixes = {
                    help = {},
                    version = {},
                    ["self-test"] = {},
                    ["model-repl"] = {},
                    ["config-repl"] = {},
                    ["context-repl"] = { "recent" },
                    ["continue"] = { "ABCDEF0123456789" },
                    ["export-context"] = { "Project Name" },
                    status = {},
                }
                for _, descriptor in ipairs(cli.registry().actions) do
                    for _, projection in ipairs(descriptor.projections) do
                        if projection.kind == "argv" and projection.long then
                            local suffix = suffixes[descriptor.id]
                            local long = { projection.long }
                            local short = { projection.short }
                            local slash = { projection.slash }
                            for _, value in ipairs(suffix) do
                                long[#long + 1] = value
                                short[#short + 1] = value
                                slash[#slash + 1] = value
                            end
                            A.equal(assert(linux.parse_argv(long, { tty = true })).id, descriptor.id)
                            A.equal(assert(linux.parse_argv(short, { tty = true })).id, descriptor.id)
                            A.equal(assert(windows.parse_argv(slash, { tty = true })).id, descriptor.id)
                        end
                    end
                end

                local linux_slash = assert(linux.parse_argv({ "/h" }, { tty = true }))
                A.equal(linux_slash.id, "run-chat")
                A.equal(linux_slash.directory, "/h")
                local windows_path = assert(windows.parse_argv({ "/work/tree" }, { tty = true }))
                A.equal(windows_path.id, "run-chat")
                A.equal(windows_path.directory, "/work/tree")
                A.equal(
                    assert(linux.parse_argv({ "--", "--help" }, { tty = true })).directory,
                    "--help"
                )
                A.equal(
                    assert(windows.parse_argv({ "--", "/h" }, { tty = true })).directory,
                    "/h"
                )
                assert_parse_error(
                    linux,
                    "parse_argv",
                    { "--help", "--version" },
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    linux,
                    "parse_argv",
                    { "one", "two" },
                    "UsageError",
                    { tty = true }
                )
            end,
        },
        {
            name = "self-test options are typed repeatable and consent is invocation-local",
            run = function()
                local service = new_service()
                local request = assert(service.parse_argv({
                    "--self-test",
                    "--through-stage", "3",
                    "--list-checks",
                    "--exclude-model", "One",
                    "--exclude-model", "Two",
                    "--exclude-check", "ST2-MODEL-AUTH",
                    "--check", "ST1-PLATFORM",
                    "--check", "ST1-PACKAGE",
                    "--i-accept-online-self-test",
                }, { tty = false }))
                A.equal(request.id, "self-test")
                A.equal(request.through_stage, 3)
                A.truthy(request.list_checks)
                A.deep_equal(request.excluded_models, { "One", "Two" })
                A.deep_equal(request.excluded_checks, { "ST2-MODEL-AUTH" })
                A.deep_equal(request.selected_checks, { "ST1-PLATFORM", "ST1-PACKAGE" })
                A.truthy(request.online_consent)

                for _, argv in ipairs({
                    { "--self-test", "--through-stage", "4" },
                    { "--self-test", "--through-stage" },
                    { "--self-test", "--through-stage", "1", "--through-stage", "2" },
                    { "--self-test", "--unknown" },
                }) do
                    assert_parse_error(
                        service,
                        "parse_argv",
                        argv,
                        "UsageError",
                        { tty = true }
                    )
                end
                assert_parse_error(
                    service,
                    "parse_argv",
                    { "--machine", "--self-test", "--through-stage", "2",
                        "--i-accept-online-self-test" },
                    "UsageError",
                    { tty = false }
                )
                local first = assert(service.parse_argv({
                    "--self-test", "--through-stage", "2",
                    "--i-accept-online-self-test",
                }, { tty = false }))
                A.truthy(first.online_consent)
                assert_parse_error(
                    service,
                    "parse_argv",
                    { "--self-test", "--through-stage", "2" },
                    "OnlineConsentRequired",
                    { tty = false }
                )
            end,
        },
        {
            name = "fd matrix keeps human pipes explicit and gates interactive surfaces",
            run = function()
                local service = new_service()
                local redirected = {
                    stdin_is_tty = true,
                    stdout_is_tty = false,
                    stderr_is_tty = false,
                }
                A.equal(service.fd_mode({ id = "help" }, redirected), "human-text")
                A.equal(service.fd_mode({ id = "version" }, redirected), "human-text")
                local request = assert(service.parse_argv({ "--help" }, redirected))
                A.falsy(request.machine)
                local _, tty_error = service.fd_mode({ id = "run-chat", directory = "." }, redirected)
                A.equal(tty_error.code, "TtyRequired")
                A.equal(service.fd_mode({ id = "run-chat", directory = "." }, {
                    stdin_is_tty = true,
                    stdout_is_tty = true,
                    stderr_is_tty = false,
                }), "human-interactive")
                A.equal(service.fd_mode({ id = "help", machine = true }, {
                    stdin_is_tty = false,
                    stdout_is_tty = false,
                    stderr_is_tty = false,
                    machine_requested = true,
                }), "machine-json-or-jsonl")
                local _, machine_error = service.fd_mode({ id = "run-chat", machine = true }, {
                    stdin_is_tty = true,
                    stdout_is_tty = true,
                    stderr_is_tty = true,
                })
                A.equal(machine_error.code, "UsageError")
                assert_parse_error(
                    service,
                    "parse_argv",
                    { "--machine", "--model-repl" },
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    service,
                    "parse_argv",
                    { "--machine", "--machine", "--help" },
                    "UsageError",
                    { tty = false }
                )
            end,
        },
        {
            name = "chat grammar projects every command without accepting legacy spelling",
            run = function()
                local service = new_service()
                local cases = {
                    { "plain message", "queue-add", "message", "plain message" },
                    { ".queue another message", "queue-add", "message", "another message" },
                    { ".queue list", "queue-list" },
                    { ".queue delete #1", "queue-delete", "queue_id", "#1" },
                    { ".queue move #1 #2", "queue-move", "to", "#2" },
                    { ".queue edit #2 replacement text", "queue-edit", "message", "replacement text" },
                    { ".queue clear", "queue-clear" },
                    { ".immediate fix it", "steer", "message", "fix it" },
                    { ".side explain it", "side", "message", "explain it" },
                    { ".multiline", "multiline" },
                    { ".cancel", "cancel" },
                    { ".cautious", "cautious", "operation", "status" },
                    { ".cautious toggle", "cautious", "operation", "toggle" },
                    { ".model Primary Model", "select-model", "selector", "Primary Model" },
                    { ".context Project Name", "select-context", "selector", "Project Name" },
                    { ".status", "status-chat" },
                    { ".help input", "help-chat", "topic", "input" },
                    { ".details event-42", "details", "error_id", "event-42" },
                    { ".prompt", "prompt-edit", "operation", "show" },
                    { ".prompt set keep exact words", "prompt-edit", "text", "keep exact words" },
                    { ".compact", "compact-manual" },
                    { ".quit", "quit" },
                }
                for _, case in ipairs(cases) do
                    local request = assert(service.parse_chat(case[1], { tty = true }))
                    A.equal(request.id, case[2], case[1])
                    if case[3] then A.equal(request[case[3]], case[4], case[1]) end
                end
                A.equal(
                    assert(service.parse_chat("  keep boundary  ", { tty = true })).message,
                    "  keep boundary  "
                )
                for _, line in ipairs({
                    ".immidiate fix it", ".queue delete #0", ".queue list extra",
                    ".cautious maybe", ".status extra", ".unknown",
                }) do
                    assert_parse_error(
                        service,
                        "parse_chat",
                        line,
                        "UsageError",
                        { tty = true }
                    )
                end
                assert_parse_error(
                    service,
                    "parse_chat",
                    ".status",
                    "TtyRequired",
                    { tty = false }
                )
            end,
        },
        {
            name = "Context REPL grammar preserves selectors names paths and confirmation",
            run = function()
                local service = new_service()
                local cases = {
                    { "export", "export-context" },
                    { "export Project Name", "export-context", "selector", "Project Name" },
                    { "select Project Name", "select-context", "selector", "Project Name" },
                    { "list", "context-list", "view", "recent" },
                    { "list full", "context-list", "view", "full" },
                    { "inspect ABCDEF0123456789", "context-inspect", "selector", "ABCDEF0123456789" },
                    { "search two exact words", "context-search", "query", "two exact words" },
                    { "rename \"Old Name\" New Name", "context-rename", "new_name", "New Name" },
                    { "rebind Project /srv/New Root", "context-rebind", "target_root", "/srv/New Root" },
                    { "delete Project --yes", "context-delete", "yes", true },
                    { "set-auto-rename-disabled Project true",
                        "context-set-auto-rename-disabled", "value", true },
                    { "import /srv/Context Files/A.xml", "context-import", "path",
                        "/srv/Context Files/A.xml" },
                    { "repair Project Name", "context-repair", "selector", "Project Name" },
                    { "refresh", "context-refresh" },
                }
                for _, case in ipairs(cases) do
                    local request = assert(service.parse_context_repl(case[1], { tty = true }))
                    A.equal(request.id, case[2], case[1])
                    if case[3] then A.equal(request[case[3]], case[4], case[1]) end
                end
                A.equal(
                    assert(service.parse_context_repl(
                        "rename \"Old Name\" New Name",
                        { tty = true }
                    )).selector,
                    "Old Name"
                )
                assert_parse_error(
                    service,
                    "parse_context_repl",
                    "select",
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    service,
                    "parse_context_repl",
                    "set-auto-rename-disabled Project maybe",
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    service,
                    "parse_context_repl",
                    "delete Project --yes trailing",
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    service,
                    "parse_context_repl",
                    "delete Project",
                    "ApprovalRequired",
                    { tty = false }
                )
                A.equal(
                    assert(service.parse_context_repl(
                        "delete Project --yes",
                        { tty = false }
                    )).id,
                    "context-delete"
                )
                assert_parse_error(
                    service,
                    "parse_context_repl",
                    "rebind Project /srv/Other",
                    "ApprovalRequired",
                    { tty = false }
                )
            end,
        },
        {
            name = "help and completion are deterministic registry projections",
            run = function()
                local linux = new_service("linux")
                local windows = new_service("windows")
                A.equal(assert(linux.render_help()), read_file("test/golden/help"))
                for _, descriptor in ipairs(cli.registry().actions) do
                    local rendered = assert(linux.render_help(descriptor.id))
                    A.contains(rendered, "Action: " .. descriptor.id)
                    A.contains(rendered, descriptor.summary)
                    for _, projection in ipairs(descriptor.projections) do
                        if projection.kind == "argv" and projection.long then
                            A.contains(rendered, projection.long)
                            A.contains(rendered, projection.short)
                            A.contains(rendered, projection.slash)
                        elseif projection.command then
                            A.contains(rendered, projection.command)
                        end
                    end
                end
                A.contains(assert(linux.render_help("chat")), ".immediate <message>")
                A.contains(assert(linux.render_help("context")), "delete <selector> [--yes]")
                A.contains(assert(linux.render_help("input")), "Ctrl+Enter")
                A.contains(assert(linux.render_help("actions")), "context-refresh")
                local missing, help_error = linux.render_help("versoin")
                A.falsy(missing)
                A.equal(help_error.code, "UsageError")
                A.equal(help_error.suggestion, "version")

                A.same_items(linux.complete("top", "--"), {
                    "--config-repl", "--context-repl", "--continue", "--export", "--help",
                    "--machine", "--model-repl", "--self-test", "--status", "--version",
                })
                A.falsy(table.concat(assert(linux.complete("top", "/")), " "):find("/h", 1, true))
                A.contains(table.concat(assert(windows.complete("top", "/")), " "), "/h")
                A.same_items(linux.complete("chat", ".queue"), {
                    ".queue", ".queue clear", ".queue delete", ".queue edit", ".queue list",
                    ".queue move",
                })
            end,
        },
        {
            name = "machine JSON and JSONL use canonical fields and a required final outcome",
            run = function()
                local codec = json_codec()
                local service = assert(cli.new({
                    platform = "linux",
                    json_codec = codec,
                }))
                local rendered = assert(service.machine_result("version", "success", {
                    version = "0.1.0-dev",
                    count = 2,
                    items = { "one", "two" },
                    metadata = {},
                }))
                A.equal(rendered:sub(-1), "\n")
                local value = assert(codec.parse(without_final_newline(rendered)))
                A.equal(value.schema_version, "yaca-cli-v0.1.0")
                A.equal(value.kind, "version")
                A.equal(value.outcome, "success")
                A.equal(assert(json.number_lexeme(value.count)), "2")
                A.equal(json.kind(value.items), "array")
                A.equal(json.kind(value.metadata), "object")

                local stream = assert(service.machine_stream("self-test", {
                    { check_id = "ST1-PLATFORM", state = "passed" },
                    { check_id = "ST1-PACKAGE", state = "passed" },
                    { outcome = "passed", checked = 2 },
                }))
                local records = {}
                for line in stream:gmatch("([^\n]+)\n") do
                    records[#records + 1] = assert(codec.parse(line))
                end
                A.equal(#records, 3)
                for index, record in ipairs(records) do
                    A.equal(record.schema_version, "yaca-cli-v0.1.0")
                    A.equal(record.kind, "self-test")
                    A.equal(assert(json.number_lexeme(record.sequence)), tostring(index))
                    A.equal(record.final, index == 3)
                end
                A.equal(records[3].outcome, "passed")

                local no_final, no_final_error = service.machine_stream("self-test", {
                    { check_id = "ST1-PLATFORM" },
                })
                A.falsy(no_final)
                A.equal(no_final_error.code, "InvalidMachineStream")
                local reserved, reserved_error = service.machine_result("version", "success", {
                    kind = "other",
                })
                A.falsy(reserved)
                A.equal(reserved_error.code, "InvalidMachineValue")
                local cyclic = {}
                cyclic.self = cyclic
                local cycle_output, cycle_error = service.machine_result(
                    "version",
                    "success",
                    { payload = cyclic }
                )
                A.falsy(cycle_output)
                A.equal(cycle_error.code, "InvalidMachineValue")
                local unavailable, unavailable_error = new_service().machine_result(
                    "version",
                    "success"
                )
                A.falsy(unavailable)
                A.equal(unavailable_error.code, "MachineCodecUnavailable")
            end,
        },
        {
            name = "exit classes and broken stdout fail closed from the registry",
            run = function()
                local service = new_service()
                local expected = {
                    success = 0,
                    general_error = 1,
                    usage = 2,
                    invalid_config = 3,
                    lock_conflict = 4,
                    interaction_required = 5,
                    resolver_negative = 6,
                    cancelled = 7,
                }
                A.deep_equal(cli.registry().exit_classes, expected)
                A.equal(service.exit_code({ outcome = "success" }), 0)
                A.equal(service.exit_code({ outcome = "ready" }), 0)
                A.equal(service.exit_code({ outcome = "partial" }), 1)
                A.equal(service.exit_code({ outcome = "unknown-outcome" }), 1)
                A.equal(service.exit_code({ code = "UsageError" }), 2)
                A.equal(service.exit_code({ code = "ConfigInvalid" }), 3)
                A.equal(service.exit_code({ code = "LockConflict" }), 4)
                A.equal(service.exit_code({ code = "TtyRequired" }), 5)
                A.equal(service.exit_code({ code = "HashCollision" }), 6)
                A.equal(service.exit_code({ code = "Cancelled" }), 7)
                A.equal(service.exit_code({ exit_class = "usage" }), 2)
                A.equal(service.exit_code({ exit_class = "unknown" }), 1)
                for _, record in ipairs(diagnostics.errors) do
                    A.equal(
                        service.exit_code({ code = record.id }),
                        diagnostics.exit_classes[record.exit_class],
                        record.id
                    )
                end

                local observed
                A.truthy(service.emit(function(bytes)
                    observed = bytes
                    return true
                end, "payload\n"))
                A.equal(observed, "payload\n")
                local emitted, output_error = service.emit(function() return false end, "x")
                A.falsy(emitted)
                A.equal(output_error.code, "BrokenStdout")
                A.truthy(output_error.close_required)
                A.equal(service.exit_code(output_error), 1)
                local raised, raised_error = service.emit(function()
                    error("closed")
                end, "x")
                A.falsy(raised)
                A.equal(raised_error.code, "BrokenStdout")
            end,
        },
        {
            name = "invalid construction argv encoding and fd facts never guess",
            run = function()
                local invalid, invalid_error = cli.new({ platform = "other" })
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidCliOptions")
                local unknown, unknown_error = cli.new({ platform = "linux", other = true })
                A.falsy(unknown)
                A.equal(unknown_error.code, "InvalidCliOptions")
                local service = new_service()
                assert_parse_error(
                    service,
                    "parse_argv",
                    { string.char(0xFF) },
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    service,
                    "parse_argv",
                    { "bad\0path" },
                    "UsageError",
                    { tty = true }
                )
                assert_parse_error(
                    service,
                    "parse_argv",
                    { [2] = "path" },
                    "UsageError",
                    { tty = true }
                )
                local request, facts_error = service.parse_argv({ "--help" }, {
                    stdin_is_tty = true,
                    stdout_is_tty = true,
                })
                A.falsy(request)
                A.equal(facts_error.code, "InvalidCliFacts")
                local mismatch, mismatch_error = service.parse_argv(
                    { "--machine", "--help" },
                    {
                        stdin_is_tty = false,
                        stdout_is_tty = false,
                        stderr_is_tty = false,
                        machine_requested = false,
                    }
                )
                A.falsy(mismatch)
                A.equal(mismatch_error.code, "InvalidCliFacts")
                local extra_fact, extra_fact_error = service.parse_argv({ "--help" }, {
                    stdin_is_tty = true,
                    stdout_is_tty = true,
                    stderr_is_tty = true,
                    ambient_guess = true,
                })
                A.falsy(extra_fact)
                A.equal(extra_fact_error.code, "InvalidCliFacts")
            end,
        },
    },
}
