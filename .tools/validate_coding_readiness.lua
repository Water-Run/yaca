--[[
Author: WaterRun
Date: 2026-09-23
File: validate_coding_readiness.lua
Description: Checks source-start gates and required evidence against the executable readiness contract.
]]

local failures = {}
local assertions = 0

-- Record one contract assertion while collecting every independent failure.
--@param value any Truthy value when the invariant holds.
--@param message string Finding to report when the invariant fails.
--@return nil No result; updates the audit counters.
--@effect Increments assertions and appends a failure message when falsey.
local function check(value, message)
  assertions = assertions + 1
  if not value then failures[#failures + 1] = message end
end

local script = (arg[0] or ""):gsub("\\", "/")
local root = script:match("^(.*)/%.tools/[^/]+$")
if not root or root == "" then root = "." end

-- Load and execute one repository-owned Lua contract table.
--@param path string Absolute or repository-relative contract file path.
--@return table Loaded contract, or an empty table after a recorded failure.
--@effect Reads and executes the file; records load and shape failures.
local function load_table(path)
  local chunk, load_error = loadfile(path)
  check(chunk ~= nil, "cannot load " .. path .. ": " .. tostring(load_error))
  if not chunk then return {} end
  local ok, value = pcall(chunk)
  check(ok and type(value) == "table", path .. " must return a table")
  if not ok or type(value) ~= "table" then return {} end
  return value
end

-- Read all bytes of an expected design or public document.
--@param path string Absolute or repository-relative document path.
--@return string File bytes, or empty bytes after a recorded open failure.
--@effect Reads the file and records an open failure when necessary.
local function read_all(path)
  local handle, open_error = io.open(path, "rb")
  check(handle ~= nil, "cannot read " .. path .. ": " .. tostring(open_error))
  if not handle then return "" end
  local bytes = handle:read("a")
  handle:close()
  return bytes
end

-- Quote one POSIX shell argument used by the local find invocation.
--@param value string Directory or pattern bytes passed as one shell word.
--@return string quoted Single-quoted POSIX shell word.
local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Enumerate matching direct child files for a fixed repository directory.
--@param directory string Directory passed to the local find command.
--@param pattern string Glob passed as one argument to find -name.
--@return table names Sorted matching basenames, or empty on start failure.
--@effect Starts find, reads its output, and records a start failure.
local function list_files(directory, pattern)
  local pipe = io.popen("find " .. shell_quote(directory) .. " -maxdepth 1 -type f -name " .. shell_quote(pattern) .. " -printf '%f\\n' 2>/dev/null", "r")
  check(pipe ~= nil, "cannot enumerate " .. directory)
  if not pipe then return {} end
  local result = {}
  for line in pipe:lines() do result[#result + 1] = line end
  pipe:close()
  table.sort(result)
  return result
end

-- Validate a string sequence and return a membership map for later checks.
--@param values table|nil String sequence; nil is treated as empty.
--@param label string Context included in invalid or duplicate findings.
--@return table set Membership map of the observed strings.
--@effect Records invalid-value and duplicate-value failures.
local function as_set(values, label)
  local result = {}
  for _, value in ipairs(values or {}) do
    check(type(value) == "string" and value ~= "", label .. " has an invalid value")
    check(result[value] == nil, label .. " repeats " .. tostring(value))
    result[value] = true
  end
  return result
end

local readiness = load_table(root .. "/.develope-docs/contracts/readiness.lua")
local release = load_table(root .. "/.develope-docs/contracts/release.lua")
local proof = load_table(root .. "/.develope-docs/proofs/modern-2026-08-29/manifest.lua")
local plan = read_all(root .. "/.develope-docs/IMPLEMENTATION-PLAN.md")
local audit = read_all(root .. "/.develope-docs/GATE-AUDIT-2026-08-29.md")
local register = read_all(root .. "/.develope-docs/DECISION-REGISTER.md")
local proof_backlog = read_all(root .. "/.develope-docs/TECHNICAL-PROOF-BACKLOG.md")
local public_en = read_all(root .. "/README.md")
local public_zh = read_all(root .. "/README-zh.md")

-- Phase truth must be explicit and non-circular.
check(readiness.gates and readiness.gates.A and readiness.gates.A.status == "passed", "Gate A is not passed")
check(readiness.gates and readiness.gates.B and readiness.gates.B.status == "passed", "Gate B is not passed")
check(readiness.gates and readiness.gates.R and readiness.gates.R.status == "closed", "Release Gate R must remain closed before edition qualification")
check(readiness.gates and readiness.gates.R and readiness.gates.R.release_authorized == false, "release must remain unauthorized")
check(readiness.gates.R.decision == "D-073" and readiness.gates.R.decision_date == "2026-09-22", "Gate R must cite the three-edition owner decision")
check(#(readiness.gates.R.pending_targets or {}) == 3, "Gate R must enumerate three pending targets")
check(proof.conclusions and proof.conclusions.target_qualification_complete == false and proof.conclusions.release_gate_open == false, "modern proof manifest must not authorize the new editions")
check(audit:find("Gate A 通过；Gate B 通过", 1, true) ~= nil, "gate audit conclusion drifted")
check(plan:find("Gate B passed", 1, true) ~= nil, "implementation plan no longer reports Gate B passed")
check(not plan:find("任选", 1, true) and not plan:find("视情况", 1, true) and not plan:find("TBD", 1, true) and not plan:find("TODO", 1, true), "implementation plan contains an unresolved choice marker")

-- Owner input is closed, not merely assumed closed.
check(register:find("`unanswered=0`", 1, true) ~= nil, "decision register no longer reports unanswered=0")
check(register:find("| `conflict` | 0 |", 1, true) ~= nil, "decision register no longer reports conflict=0")
check(register:find("| Formal groups | 270 |", 1, true) ~= nil, "decision inventory size drifted")
for index = 1, 30 do
  local id = string.format("TP-%03d", index)
  local heading_start = proof_backlog:find("### " .. id, 1, true)
  local next_start = proof_backlog:find("### TP-", (heading_start or 0) + 1, true)
  local section = heading_start and proof_backlog:sub(heading_start, next_start and next_start - 1 or #proof_backlog) or ""
  check(heading_start ~= nil, "proof backlog omits " .. id)
  check(section:find("**当前状态**", 1, true) ~= nil, "proof backlog has no phase status for " .. id)
  check(section:find("`unplanned`", 1, true) == nil, "Gate A cannot pass with unplanned proof " .. id)
end

-- Every machine task and milestone must be visible in the human execution plan.
local task_ids = {}
for _, task in ipairs(readiness.tasks or {}) do
  check(type(task.id) == "string" and task.id:match("^C%d%d$"), "invalid coding task id")
  check(not task_ids[task.id], "duplicate coding task " .. tostring(task.id))
  task_ids[task.id] = true
  check(plan:find(task.id, 1, true) ~= nil, "implementation plan omits " .. task.id)
  check(plan:find(task.commit, 1, true) ~= nil, "implementation plan omits commit boundary for " .. task.id)
  for _, file in ipairs(task.files or {}) do check(plan:find(file, 1, true) ~= nil, "implementation plan omits file boundary " .. task.id .. "/" .. file) end
end
for index = 1, 34 do check(task_ids[string.format("C%02d", index)], "missing coding task C" .. string.format("%02d", index)) end
local milestone_ids = {}
for _, milestone in ipairs(readiness.milestones or {}) do
  milestone_ids[#milestone_ids + 1] = milestone.id
  check(plan:find(milestone.id, 1, true) ~= nil, "implementation plan omits " .. tostring(milestone.id))
end
local milestone_set = as_set(milestone_ids, "milestones")
for index = 0, 10 do check(milestone_set["M" .. index], "missing implementation milestone M" .. index) end
check(readiness.gates.B.first_task == "C01" and readiness.source_start.first_task == "C01", "first coding task drifted")

-- Every architecture gate must be audited and routed to a real task.
for _, item in ipairs(readiness.gate_a_items or {}) do
  check(audit:find(item.id, 1, true) ~= nil, "gate audit omits " .. tostring(item.id))
  check(task_ids[item.implementation_task], "gate item routes to unknown task " .. tostring(item.id))
  if item.status == "qualification-bound" then check(item.hard_gate ~= "" and item.hard_gate ~= "none", "qualification-bound item has no hard gate: " .. tostring(item.id)) end
end
check(#(readiness.gate_a_items or {}) == 28, "Gate A audit must contain 28 P0/P1 items")

-- Source inventory and public truth follow an explicit implementation phase.
local source_files = list_files(root .. "/src", "*.lua")
local phase = readiness.source_start and readiness.source_start.implementation_phase
local phase_set = as_set(readiness.source_start and readiness.source_start.allowed_implementation_phases or {}, "implementation phases")
check(phase_set[phase], "invalid implementation phase")
check(phase == "implemented-unqualified", "new editions remain implemented but unqualified")
check(readiness.source_start.release_is_not_authorized == true, "source phase must withhold release authority")
check(readiness.source_start and readiness.source_start.source_is_currently_skeleton_only == (phase == "pre-coding"), "skeleton flag disagrees with implementation phase")
local planned_sources = {}
for _, module_id in ipairs(release.planned_lua_modules or {}) do planned_sources[module_id .. ".lua"] = true end
local initial_sources = {}
for _, module_id in ipairs(release.initial_skeleton_modules or {}) do initial_sources[module_id .. ".lua"] = true end
local nonempty_sources = 0
for _, filename in ipairs(source_files) do
  check(planned_sources[filename], "unexpected product source module: " .. filename)
  if #read_all(root .. "/src/" .. filename) > 0 then nonempty_sources = nonempty_sources + 1 end
end
if phase == "pre-coding" then
  check(#source_files == #(release.initial_skeleton_modules or {}), "pre-coding source skeleton file count drifted")
  for _, filename in ipairs(source_files) do check(initial_sources[filename], "unexpected source module before coding: " .. filename) end
  check(nonempty_sources == 0, "product source was written before coding-start transition")
  check(proof.conclusions and proof.conclusions.product_source_written == false, "pre-coding phase disagrees with captured proof milestone")
elseif phase == "implementing" then
  check(nonempty_sources > 0, "implementing phase has no written product source")
elseif phase == "implemented-unqualified" or phase == "released" then
  check(#source_files == #(release.planned_lua_modules or {}), "implemented source inventory is incomplete")
  check(nonempty_sources == #source_files, "implemented source inventory still contains empty skeletons")
end

local marker = readiness.source_start and readiness.source_start.public_status_markers and readiness.source_start.public_status_markers[phase]
check(marker and public_en:find(marker.en, 1, true) ~= nil, "English README does not match implementation phase")
check(marker and public_zh:find(marker.zh, 1, true) ~= nil, "Chinese README does not match implementation phase")
check(marker and plan:find(marker.plan, 1, true) ~= nil, "implementation plan header does not match implementation phase")
local web_files = list_files(root .. "/web", "*")
check(#web_files == 1 and web_files[1] == "README.md", "v0.1 web directory is no longer zero-surface")

if #failures > 0 then
  io.stderr:write(string.format("coding-readiness validation FAILED: %d failure(s), %d assertions\n", #failures, assertions))
  for _, failure in ipairs(failures) do io.stderr:write("- " .. failure .. "\n") end
  os.exit(1)
end

io.stdout:write(string.format("coding-readiness validation PASS: %d assertions; Gate A/B passed, Release Gate R closed per D-073\n", assertions))
