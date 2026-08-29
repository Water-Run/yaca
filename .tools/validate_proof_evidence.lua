local failures = {}
local assertions = 0

local function check(value, message)
  assertions = assertions + 1
  if not value then failures[#failures + 1] = message end
end

local script = (arg[0] or ""):gsub("\\", "/")
local root = script:match("^(.*)/%.tools/[^/]+$")
if not root or root == "" then root = "." end

local manifest_path = root .. "/.develope-docs/proofs/modern-2026-08-29/manifest.lua"
local chunk, load_error = loadfile(manifest_path)
check(chunk ~= nil, "cannot load proof manifest: " .. tostring(load_error))
local ok, manifest = false, nil
if chunk then ok, manifest = pcall(chunk) end
check(ok and type(manifest) == "table", "proof manifest must return a table")
if not ok or type(manifest) ~= "table" then manifest = {} end

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function sha256(path)
  local pipe = io.popen("sha256sum " .. shell_quote(path), "r")
  if not pipe then return nil end
  local line = pipe:read("l") or ""
  pipe:close()
  return line:match("^([0-9a-f]+)")
end

local expected = {
  ["TP-003"] = {
    [root .. "/.tools/proofs/tp003_event_pump.lua"] = "2133be3a0cfb4e489d5268d2c11beec875f4558c638a9672a9321ba5d914a418",
  },
  ["TP-006"] = {
    [root .. "/.tools/proofs/tp006_curl_carrier.py"] = "8103e6e0d902526f2fc6068a8baef828a121611538d8b577ca876388109241ff",
  },
  ["TP-008"] = {
    [root .. "/.tools/proofs/tp008_xml_commit.py"] = "a7e4db216d3ed15625eca76dbba0b3119d51158e2ac1478aa51c2c6d9a597566",
  },
  ["TP-010"] = {
    [root .. "/.tools/proofs/tp010_build.sh"] = "6ccda002fba1802349463c3d025341abd22d0cede755784974954122e4a1083c",
    [root .. "/.tools/proofs/tp010_xml.lua"] = "11e5ad1953193fa7477401bd197a8ef807ca713ca3944323a043be9fc5f557e2",
  },
}

local seen = {}
for _, proof in ipairs(manifest.proofs or {}) do
  check(expected[proof.id] ~= nil, "unexpected proof id " .. tostring(proof.id))
  check(not seen[proof.id], "duplicate proof id " .. tostring(proof.id))
  seen[proof.id] = true
  check(proof.status == "proven-modern", tostring(proof.id) .. " status must be proven-modern")
  check(type(proof.scope) == "string" and proof.scope ~= "", tostring(proof.id) .. " has no scope")
  check(type(proof.command) == "string" and proof.command ~= "", tostring(proof.id) .. " has no reproduction command")
  check(type(proof.assertions) == "number" and proof.assertions > 0, tostring(proof.id) .. " has no assertion count")
  check(type(proof.target_pending) == "table" and #proof.target_pending > 0, tostring(proof.id) .. " must retain target qualification")
end
for id in pairs(expected) do check(seen[id], "proof manifest omits " .. id) end

for id, files in pairs(expected) do
  for path, digest in pairs(files) do
    check(sha256(path) == digest, id .. " proof source digest drifted: " .. path)
  end
end

for name, pin in pairs(manifest.source_pins or {}) do
  check(type(pin.version) == "string" and pin.version ~= "", name .. " has no source version")
  check(type(pin.sha256) == "string" and pin.sha256:match("^[0-9a-f]+$") and #pin.sha256 == 64, name .. " has invalid SHA-256")
  check(type(pin.url) == "string" and pin.url:match("^https://"), name .. " source URL must be HTTPS")
end
check(manifest.source_pins and manifest.source_pins.lua and manifest.source_pins.expat and manifest.source_pins.luaexpat, "proof manifest must pin all three TP-010 sources")
check(manifest.conclusions and manifest.conclusions.target_qualification_complete == false, "modern proof must not claim target qualification")
check(manifest.conclusions and manifest.conclusions.release_gate_open == false, "modern proof must not open release gate")
check(manifest.conclusions and manifest.conclusions.product_source_written == false, "proof milestone must not write product source")

if #failures > 0 then
  io.stderr:write(("proof-evidence validation FAILED: %d failure(s), %d assertions\n"):format(#failures, assertions))
  for _, failure in ipairs(failures) do io.stderr:write("- " .. failure .. "\n") end
  os.exit(1)
end

print(("proof-evidence validation PASS: %d assertions across 4 modern proofs"):format(assertions))
