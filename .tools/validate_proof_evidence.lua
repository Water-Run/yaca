--[[
Author: WaterRun
Date: 2026-09-23
File: validate_proof_evidence.lua
Description: Checks proof manifests, declared artifacts and evidence admission requirements.
]]

local failures = {}
local assertions = 0

-- Records a failed proof invariant while retaining all findings for one report.
--@param value any Truthy when the invariant holds.
--@param message string Diagnostic recorded when value is false.
--@return nil No return value; increments the assertion count and may append a finding.
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

-- Quotes a path for the sha256sum command without admitting shell substitutions.
--@param value string Path passed to the command shell.
--@return string quoted Argument quoted for the selected command shell.
local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Reads the SHA-256 digest of one proof source file.
--@param path string Absolute or repository-relative proof source path.
--@return string|nil digest Lowercase hexadecimal digest, or nil if the command cannot read it.
local function sha256(path)
  local pipe = io.popen("sha256sum " .. shell_quote(path), "r")
  if not pipe then return nil end
  local line = pipe:read("l") or ""
  pipe:close()
  return line:match("^([0-9a-f]+)")
end

local expected = {
  ["TP-003"] = {
    files = {
      [root .. "/.tools/proofs/tp003_event_pump.lua"] = "8a7ead513c41dea5463555602f7dc5e3c04959133ebc9c3cfaaa4c2f993d44db",
    },
    recorded = "8a7ead513c41dea5463555602f7dc5e3c04959133ebc9c3cfaaa4c2f993d44db",
  },
  ["TP-006"] = {
    files = {
      [root .. "/.tools/proofs/tp006_curl_carrier.py"] = "ca9d36a85f3f4cc8fde3e75a5f2572114da18e2251b9df6926769d87575dba78",
    },
    recorded = "ca9d36a85f3f4cc8fde3e75a5f2572114da18e2251b9df6926769d87575dba78",
  },
  ["TP-008"] = {
    files = {
      [root .. "/.tools/proofs/tp008_xml_commit.py"] = "cabd182deb12b606566d4d8d56e33404049ef8fb644944ff4228026cb7d8c407",
    },
    recorded = "cabd182deb12b606566d4d8d56e33404049ef8fb644944ff4228026cb7d8c407",
  },
  ["TP-010"] = {
    files = {
      [root .. "/.tools/proofs/tp010_build.sh"] = "8199ac07ea85ee5c404d6b97515ea94252239301cc981d701cda9016546de5c3",
      [root .. "/.tools/proofs/tp010_xml.lua"] = "b31f2d3747df5244ba11e90f77572e35125932573b89b6a66a033becff0f8dd1",
    },
    recorded = {
      build = "8199ac07ea85ee5c404d6b97515ea94252239301cc981d701cda9016546de5c3",
      corpus = "b31f2d3747df5244ba11e90f77572e35125932573b89b6a66a033becff0f8dd1",
    },
  },
}

-- Compares either scalar digests or keyed digest maps without ignoring extra keys.
--@param actual string|table Digest or digest map loaded from the manifest.
--@param wanted string|table Independently pinned digest or digest map.
--@return boolean matches True only when the digest values and map keys match exactly.
local function same_digest_record(actual, wanted)
  if type(wanted) == "string" then return actual == wanted end
  if type(actual) ~= "table" or type(wanted) ~= "table" then return false end
  local actual_count = 0
  local wanted_count = 0
  for key, value in pairs(actual) do
    actual_count = actual_count + 1
    if wanted[key] ~= value then return false end
  end
  for _ in pairs(wanted) do wanted_count = wanted_count + 1 end
  return actual_count == wanted_count
end

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
  if expected[proof.id] then
    check(same_digest_record(proof.source_sha256, expected[proof.id].recorded), tostring(proof.id) .. " manifest source digest drifted")
  end
end
for id in pairs(expected) do check(seen[id], "proof manifest omits " .. id) end

for id, proof_expected in pairs(expected) do
  for path, digest in pairs(proof_expected.files) do
    check(sha256(path) == digest, id .. " proof source digest drifted: " .. path)
  end
end

for name, pin in pairs(manifest.source_pins or {}) do
  check(type(pin.version) == "string" and pin.version ~= "", name .. " has no source version")
  check(type(pin.sha256) == "string" and pin.sha256:match("^[0-9a-f]+$") and #pin.sha256 == 64, name .. " has invalid SHA-256")
  check(type(pin.url) == "string" and pin.url:match("^https://"), name .. " source URL must be HTTPS")
end
check(manifest.source_pins and manifest.source_pins.lua and manifest.source_pins.expat and manifest.source_pins.luaexpat, "proof manifest must pin all three TP-010 sources")
check(manifest.conclusions and manifest.conclusions.target_qualification_complete == false, "modern proofs do not qualify the release targets")
check(manifest.conclusions and manifest.conclusions.release_gate_open == false, "modern proofs must retain the closed release gate")
check(manifest.conclusions and manifest.conclusions.product_source_written == true, "proof milestone must record written product source")

if #failures > 0 then
  io.stderr:write(("proof-evidence validation FAILED: %d failure(s), %d assertions\n"):format(#failures, assertions))
  for _, failure in ipairs(failures) do io.stderr:write("- " .. failure .. "\n") end
  os.exit(1)
end

print(("proof-evidence validation PASS: %d assertions across 4 modern proofs"):format(assertions))
