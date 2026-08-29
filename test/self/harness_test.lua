local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local runner = YACA_TEST_RUNNER

return {
  name = "self/harness",
  cases = {
    {
      name = "assertion helpers compare values and errors",
      run = function()
        A.equal("x", "x")
        A.deep_equal({ a = 1, nested = { true, false } }, { nested = { true, false }, a = 1 })
        A.same_items({ "b", "a", "b" }, { "a", "b", "b" })
        A.raises(function() A.equal(1, 2) end, "expected 2")
      end,
    },
    {
      name = "discovery is sorted and finds self tests",
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
      run = function()
        local valid, validation_error = runner.validate_spec({
          name = "duplicate",
          cases = {
            { name = "same", run = function() end },
            { name = "same", run = function() end },
          },
        }, "synthetic.lua")
        A.falsy(valid)
        A.contains(validation_error, "repeats case same")
      end,
    },
    {
      name = "test files receive isolated globals",
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
      run = function()
        local later_ran, output = false, {}
        local summary = runner.run_cases({
          { suite = "synthetic", name = "fails", run = function() os.exit(9) end },
          { suite = "synthetic", name = "continues", run = function() later_ran = true end },
        }, function(line) output[#output + 1] = line end)
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
