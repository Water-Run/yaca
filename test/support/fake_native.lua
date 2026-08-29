local M = {}

local function copy_table(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = item end
  return result
end

function M.platform(response, probe_error)
  local calls = 0
  local port = {}

  function port.platform_identity()
    calls = calls + 1
    if type(response) == "function" then return response(calls) end
    if response == nil then return nil, probe_error end
    return copy_table(response)
  end

  function port.call_count()
    return calls
  end

  return port
end

return M
