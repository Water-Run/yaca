--[[
Author: WaterRun
Date: 2026-09-23
File: harness_test.lua
Description: Verifies test discovery, isolation, assertions, and failure handling.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local runner = YACA_TEST_RUNNER

return {
    name = "self/harness",
    cases = {
        {
            name = "assertion helpers compare values and errors",
            --Verifies assertion helpers compare values and errors.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify assertion helpers compare values and errors.
            run = function()
                A.equal("x", "x")
                A.deep_equal({ a = 1, nested = { true, false } }, { nested = { true, false }, a = 1 })
                A.same_items({ "b", "a", "b" }, { "a", "b", "b" })
                --Executes the action expected to raise in the 'assertion helpers compare values and errors' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify assertion helpers compare values and errors.
                A.raises(function() A.equal(1, 2) end, "expected 2")
            end,
        },
        {
            name = "discovery is sorted and finds self tests",
            --Verifies assertion helpers compare values and errors.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify assertion helpers compare values and errors.
            run = function()
                local files, discovery_error = runner.discover({ YACA_TEST_ROOT .. "/test/self" })
                A.truthy(files, discovery_error)
                A.truthy(#files >= 2)
                for index = 2, #files do A.truthy(files[index - 1] < files[index], "discovery order is not stable") end
                A.matches(files[1], "_test%.lua$")
            end,
        },
        {
            name = "suite validation rejects duplicate cases",
            --Verifies discovery is sorted and finds self tests.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify discovery is sorted and finds self tests.
            run = function()
                local valid, validation_error = runner.validate_spec({
                    name = "duplicate",
                    cases = {
                        { name = "same",
                            --Verifies duplicate.
                            --@param none No arguments; this closure uses its captured fixture state.
                            --@return nil No value; assertions verify duplicate.
                            run = function() end },
                        { name = "same",
                            --Verifies duplicate.
                            --@param none No arguments; this closure uses its captured fixture state.
                            --@return nil No value; assertions verify duplicate.
                            run = function() end },
                    },
                }, "synthetic.lua")
                A.falsy(valid)
                A.contains(validation_error, "repeats case same")
            end,
        },
        {
            name = "test files receive isolated globals",
            --Verifies suite validation rejects duplicate cases.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify suite validation rejects duplicate cases.
            run = function()
                local temporary = os.tmpname()
                local handle = assert(io.open(temporary, "wb"))
                handle:write("LEAK_FROM_SYNTHETIC_TEST = true\nreturn { name = 'synthetic', cases = { { name = 'ok', run = function() end } } }\n")
                handle:close()
                local spec, load_error = runner.load_spec(temporary, YACA_TEST_ROOT)
                os.remove(temporary)
                A.truthy(spec, load_error)
                A.equal(rawget(_G, "LEAK_FROM_SYNTHETIC_TEST"), nil)
            end,
        },
        {
            name = "case failures do not prevent later cases",
            --Verifies test files receive isolated globals.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify test files receive isolated globals.
            run = function()
                local later_ran, output = false, {}
                local summary = runner.run_cases({
                    { suite = "synthetic", name = "fails",
                        --Verifies case failures do not prevent later cases.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil No value; assertions verify case failures do not prevent later cases.
                        run = function() os.exit(9) end },
                    { suite = "synthetic", name = "continues",
                        --Verifies case failures do not prevent later cases.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil No value; assertions verify case failures do not prevent later cases.
                        run = function() later_ran = true end },
                },
                    --Supplies an assertion callback for the case failures do not prevent later cases scenario.
                    --@param line string|integer Input line or physical line position.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    function(line) output[#output + 1] = line end)
                A.equal(summary.total, 2)
                A.equal(summary.failed, 1)
                A.equal(summary.passed, 1)
                A.truthy(later_ran)
                A.contains(table.concat(output, "\n"), "test attempted os.exit(9)")
                A.contains(table.concat(output, "\n"), "SUMMARY total=2 passed=1 failed=1")
            end,
        },
    },
}
