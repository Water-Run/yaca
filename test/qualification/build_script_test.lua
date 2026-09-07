--[[
File: build_script_test.lua
Date: 2026-09-07
Author: WaterRun
Description: Checks Linux build admission and rejects incomplete test evidence.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function read_file(path)
    local file = assert(io.open(YACA_TEST_ROOT .. "/" .. path, "rb"))
    local source = assert(file:read("a"))
    assert(file:close())
    return source
end

return {
    name = "qualification/build-script",
    cases = {
        {
            name = "Linux builder admits serial work with its own five GiB guard floor",
            run = function()
                local source = read_file(".tools/qualification/build_linux_x86_64.sh")
                A.contains(source, "BUILD_MINIMUM_AVAILABLE_MIB=5120")
                A.contains(source,
                    "YACA_TEST_MIN_AVAILABLE_MIB=$BUILD_MINIMUM_AVAILABLE_MIB")
                A.contains(source, "YACA_LINUX_BUILD_RESOURCE_GUARD_HELD")
                A.contains(source, 'run_with_resource_guard.sh"')
                A.contains(source, "export MAKEFLAGS=-j1")
                A.contains(source, "export MFLAGS=-j1")
                for line in source:gmatch("[^\n]+") do
                    if line:match("^%s*make ") or line:match("^if ! make ") then
                        A.contains(line, "-j1")
                    end
                end
                A.falsy(source:find("-j2", 1, true))
                A.falsy(source:find("329/329", 1, true))
                A.falsy(source:find("total=329", 1, true))
                A.contains(source, '"$SCRIPT_DIR/test_summary.lua"')
                A.contains(source, 'echo "full_tests=$FULL_TEST_COUNTS"')
                A.contains(source, 'echo "target_qualification_complete=false"')
                A.contains(source, 'echo "release_authorized=false"')
            end,
        },
        {
            name = "test evidence accepts one positive complete summary with dynamic counts",
            run = function()
                local summary = assert(loadfile(
                    YACA_TEST_ROOT .. "/.tools/qualification/test_summary.lua", "t", _ENV
                ))()
                for _, count in ipairs({ 1, 329, 442, 507 }) do
                    local source = "PASS suite :: case\nSUMMARY total=" .. count
                        .. " passed=" .. count .. " failed=0\n"
                    local result = assert(summary.parse(source))
                    A.equal(result.total, count)
                    A.equal(result.passed, count)
                    A.equal(result.failed, 0)
                    A.equal(assert(summary.parse(source:gsub("\n", "\r\n"))).total,
                        count)
                end
            end,
        },
        {
            name = "test evidence rejects missing duplicate malformed zero or failed summaries",
            run = function()
                local summary = assert(loadfile(
                    YACA_TEST_ROOT .. "/.tools/qualification/test_summary.lua", "t", _ENV
                ))()
                local valid = "SUMMARY total=442 passed=442 failed=0\n"
                for _, source in ipairs({
                    "", "PASS a single case\n", valid .. valid,
                    valid .. "SUMMARY incomplete\n",
                    "SUMMARY total=0 passed=0 failed=0\n",
                    "SUMMARY total=442 passed=441 failed=0\n",
                    "SUMMARY total=442 passed=441 failed=1\n",
                    "SUMMARY total=0442 passed=0442 failed=0\n",
                    "SUMMARY total=442 passed=442 failed=0 extra\n",
                    "SUMMARY total=-1 passed=-1 failed=0\n",
                    "SUMMARY total=999999999999999999999 passed=1 failed=0\n",
                }) do
                    local result, parse_error = summary.parse(source)
                    A.falsy(result, source)
                    A.type(parse_error, "string")
                end
            end,
        },
    },
}
