--[[
Author: WaterRun
Date: 2026-09-23
File: tp010_xml.lua
Description: TP-010 modern-host Lua-side XML, UTF-8, and carrier corpus.
]]

-- TP-010 modern-host Lua-side XML, UTF-8, and carrier corpus.
-- Executed with the pinned Lua 5.5.1 + LuaExpat/Expat build from tp010_build.sh.

local lxp = require "lxp"

local fixture_path = assert(arg[1], "missing context fixture path")
local rng_path = assert(arg[2], "missing Relax NG path")
local assertions = 0

-- Counts one corpus assertion and stops the proof on failure.
--@param value any Truthy assertion result.
--@param message string Explanation included in the failure report.
--@return nil No value; increments the assertion count.
--@error Raises with the numbered assertion when value is false.
local function check(value, message)
  assertions = assertions + 1
  if not value then
    error(("assertion %d failed: %s"):format(assertions, message), 2)
  end
end

--Asserts that observed and expected values agree in tp010 xml.
--@param actual any Observed value compared by the assertion.
--@param expected any Expected value used by the assertion.
--@param message string Explanation included in the mismatch report.
--@return nil No value; checks equality and increments the assertion count.
--@error Raises through check when actual differs from expected.
local function equal(actual, expected, message)
  check(actual == expected, ("%s (expected=%s actual=%s)"):format(
    message,
    tostring(expected),
    tostring(actual)
  ))
end

-- Reads the complete fixture file and verifies that it closes cleanly.
--@param path string Path of the XML or schema fixture.
--@return string bytes Exact file contents.
--@error Raises when open, read, or close fails.
local function read_all(path)
  local handle, open_error = io.open(path, "rb")
  check(handle ~= nil, "open " .. path .. ": " .. tostring(open_error))
  local data = assert(handle:read("a"))
  assert(handle:close())
  return data
end

-- Decodes strict UTF-8 while rejecting overlong, surrogate, and out-of-range sequences.
--@param value string Raw bytes to decode.
--@return table|nil codepoints Ordered Unicode scalar values, or nil on invalid UTF-8.
--@return string|nil reason Stable rejection reason when decoding fails.
local function strict_utf8_codepoints(value)
  local result = {}
  local index = 1
  local length = #value
  while index <= length do
    local b1 = value:byte(index)
    local codepoint
    local width
    if b1 <= 0x7f then
      codepoint = b1
      width = 1
    elseif b1 >= 0xc2 and b1 <= 0xdf then
      if index + 1 > length then return nil, "truncated-utf8" end
      local b2 = value:byte(index + 1)
      if b2 < 0x80 or b2 > 0xbf then return nil, "invalid-continuation" end
      codepoint = (b1 - 0xc0) * 0x40 + (b2 - 0x80)
      width = 2
    elseif b1 >= 0xe0 and b1 <= 0xef then
      if index + 2 > length then return nil, "truncated-utf8" end
      local b2, b3 = value:byte(index + 1, index + 2)
      if b3 < 0x80 or b3 > 0xbf then return nil, "invalid-continuation" end
      if b1 == 0xe0 then
        if b2 < 0xa0 or b2 > 0xbf then return nil, "overlong-utf8" end
      elseif b1 == 0xed then
        if b2 < 0x80 or b2 > 0x9f then return nil, "surrogate" end
      elseif b2 < 0x80 or b2 > 0xbf then
        return nil, "invalid-continuation"
      end
      codepoint = (b1 - 0xe0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
      width = 3
    elseif b1 >= 0xf0 and b1 <= 0xf4 then
      if index + 3 > length then return nil, "truncated-utf8" end
      local b2, b3, b4 = value:byte(index + 1, index + 3)
      if b3 < 0x80 or b3 > 0xbf or b4 < 0x80 or b4 > 0xbf then
        return nil, "invalid-continuation"
      end
      if b1 == 0xf0 then
        if b2 < 0x90 or b2 > 0xbf then return nil, "overlong-utf8" end
      elseif b1 == 0xf4 then
        if b2 < 0x80 or b2 > 0x8f then return nil, "above-unicode-maximum" end
      elseif b2 < 0x80 or b2 > 0xbf then
        return nil, "invalid-continuation"
      end
      codepoint = (b1 - 0xf0) * 0x40000
        + (b2 - 0x80) * 0x1000
        + (b3 - 0x80) * 0x40
        + (b4 - 0x80)
      width = 4
    else
      return nil, "invalid-leading-byte"
    end
    if codepoint > 0x10ffff then return nil, "above-unicode-maximum" end
    if codepoint >= 0xd800 and codepoint <= 0xdfff then return nil, "surrogate" end
    result[#result + 1] = codepoint
    index = index + width
  end
  return result
end

-- Encodes one valid Unicode scalar as its shortest UTF-8 sequence.
--@param codepoint integer Unicode scalar value admitted by the caller.
--@return string bytes One to four UTF-8 bytes.
local function encode_codepoint(codepoint)
  if codepoint <= 0x7f then
    return string.char(codepoint)
  elseif codepoint <= 0x7ff then
    return string.char(
      0xc0 + (codepoint // 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint <= 0xffff then
    return string.char(
      0xe0 + (codepoint // 0x1000),
      0x80 + ((codepoint // 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  end
  return string.char(
    0xf0 + (codepoint // 0x40000),
    0x80 + ((codepoint // 0x1000) % 0x40),
    0x80 + ((codepoint // 0x40) % 0x40),
    0x80 + (codepoint % 0x40)
  )
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_REVERSE = {}
for index = 1, #BASE64_ALPHABET do
  BASE64_REVERSE[BASE64_ALPHABET:byte(index)] = index - 1
end

-- Encodes arbitrary bytes with the XML carrier's Base64 alphabet and padding.
--@param value string Raw binary data.
--@return string encoded Base64 text.
local function base64_encode(value)
  local output = {}
  local index = 1
  while index <= #value do
    local b1 = value:byte(index) or 0
    local b2 = value:byte(index + 1)
    local b3 = value:byte(index + 2)
    local packed = b1 * 0x10000 + (b2 or 0) * 0x100 + (b3 or 0)
    output[#output + 1] = BASE64_ALPHABET:sub((packed // 0x40000) % 64 + 1, (packed // 0x40000) % 64 + 1)
    output[#output + 1] = BASE64_ALPHABET:sub((packed // 0x1000) % 64 + 1, (packed // 0x1000) % 64 + 1)
    output[#output + 1] = b2 and BASE64_ALPHABET:sub((packed // 0x40) % 64 + 1, (packed // 0x40) % 64 + 1) or "="
    output[#output + 1] = b3 and BASE64_ALPHABET:sub(packed % 64 + 1, packed % 64 + 1) or "="
    index = index + 3
  end
  return table.concat(output)
end

-- Decodes the Base64 carrier while checking length, alphabet, and padding.
--@param value string Candidate Base64 text.
--@return string|nil bytes Decoded bytes, or nil when the carrier is invalid.
--@return string|nil reason Stable Base64 rejection reason on failure.
local function base64_decode(value)
  if #value % 4 ~= 0 then return nil, "invalid-base64-length" end
  local output = {}
  for index = 1, #value, 4 do
    local c1, c2, c3, c4 = value:byte(index, index + 3)
    local v1, v2 = BASE64_REVERSE[c1], BASE64_REVERSE[c2]
    local v3 = c3 == 61 and 0 or BASE64_REVERSE[c3]
    local v4 = c4 == 61 and 0 or BASE64_REVERSE[c4]
    if v1 == nil or v2 == nil or v3 == nil or v4 == nil then return nil, "invalid-base64-character" end
    local packed = v1 * 0x40000 + v2 * 0x1000 + v3 * 0x40 + v4
    output[#output + 1] = string.char((packed // 0x10000) % 0x100)
    if c3 ~= 61 then output[#output + 1] = string.char((packed // 0x100) % 0x100) end
    if c4 ~= 61 then output[#output + 1] = string.char(packed % 0x100) end
    if c3 == 61 and c4 ~= 61 then return nil, "invalid-base64-padding" end
    if (c3 == 61 or c4 == 61) and index + 3 ~= #value then return nil, "early-base64-padding" end
  end
  return table.concat(output)
end

-- Checks whether a scalar may appear as an XML 1.0 character.
--@param codepoint integer Unicode scalar value.
--@return boolean allowed Whether XML 1.0 admits the scalar.
local function xml10_character(codepoint)
  return codepoint == 0x09
    or codepoint == 0x0a
    or codepoint == 0x0d
    or (codepoint >= 0x20 and codepoint <= 0xd7ff)
    or (codepoint >= 0xe000 and codepoint <= 0xfffd)
    or (codepoint >= 0x10000 and codepoint <= 0x10ffff)
end

-- Checks whether literal XML text preserves the scalar without CR normalization.
--@param codepoint integer Unicode scalar value.
--@return boolean lossless True for XML 1.0 characters other than CR.
local function xml_text_lossless(codepoint)
  -- XML parsers normalize literal CR and CRLF. Route CR-bearing scalar values
  -- through base64 so canonical bytes survive exactly.
  return xml10_character(codepoint) and codepoint ~= 0x0d
end

-- Escapes all XML text and attribute metacharacters.
--@param value string UTF-8 text selected for the XML carrier.
--@return string escaped Text with the five XML metacharacters replaced.
local function xml_escape(value)
  return (value
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
    :gsub("'", "&apos;"))
end

-- Chooses literal XML or Base64 for one optional UTF-8 scalar field.
--@param value string|nil UTF-8 field bytes, or nil for a missing field.
--@return table|nil field Presence, representation, byte count, and carrier; nil on invalid UTF-8.
--@return string|nil reason Invalid-scalar reason when strict UTF-8 decoding fails.
local function encode_scalar(value)
  if value == nil then
    return { presence = "missing" }
  end
  local codepoints, decode_error = strict_utf8_codepoints(value)
  if not codepoints then return nil, "invalid-scalar:" .. decode_error end
  local text = true
  for _, codepoint in ipairs(codepoints) do
    if not xml_text_lossless(codepoint) then
      text = false
      break
    end
  end
  if text then
    return {
      presence = "present",
      representation = "text",
      raw_bytes = #value,
      carrier = xml_escape(value),
    }
  end
  return {
    presence = "present",
    representation = "base64",
    raw_bytes = #value,
    carrier = base64_encode(value),
  }
end

-- Encodes a present binary field through the Base64 XML carrier.
--@param value string Raw binary field bytes.
--@return table field Presence, representation, byte count, and Base64 carrier.
local function encode_binary(value)
  return {
    presence = "present",
    representation = "base64",
    raw_bytes = #value,
    carrier = base64_encode(value),
  }
end

-- Decodes one field carrier and checks the declared raw byte count.
--@param field table Parsed field presence, representation, carrier, and raw_bytes.
--@return string|nil bytes Restored field bytes, or nil when presence is missing.
--@return string|nil reason The missing marker when no field was present.
--@error Raises when Base64 or raw byte count is invalid.
local function decode_carrier(field)
  if field.presence == "missing" then return nil, "missing" end
  local result
  if field.representation == "base64" then
    result = assert(base64_decode(field.carrier))
  else
    result = field.carrier
  end
  equal(#result, field.raw_bytes, "carrier raw byte count matches")
  return result
end

local CONTEXT_ELEMENTS = {
  YacaContext = true,
  Header = true,
  Name = true,
  CreatedAt = true,
  UpdatedAt = true,
  AutoRenameDisabled = true,
  NamingWaterline = true,
  AutoNameBaseline = true,
  Session = true,
  CurrentModel = true,
  CurrentPermission = true,
  DoubleCheckOverride = true,
  DoubleCheckGoalOverride = true,
  ContextPrompt = true,
  Facts = true,
  Event = true,
  Field = true,
  ModelView = true,
  ActiveManifest = true,
  CompactionRecord = true,
}

-- Parses bounded XML chunks, rejects forbidden constructs, and records SAX facts.
--@param document string Complete XML bytes used for the total-size bound.
--@param chunks table Ordered byte chunks sent to the parser.
--@param options table|nil Optional limits, Context-name checks, and SAX observers.
--@return boolean|nil accepted True after complete parse, or nil on rejection.
--@return string|nil reason Parser, security, schema, or limit failure when rejected.
--@return table state Depth, element and text counts, external-call count, and names.
local function parse_document(document, chunks, options)
  options = options or {}
  local limits = options.limits or {
    total_bytes = 1024 * 1024,
    depth = 64,
    elements = 10000,
    attributes = 64,
    text_bytes = 256 * 1024,
  }
  local state = {
    depth = 0,
    elements = 0,
    text_bytes = 0,
    external_calls = 0,
    names = {},
  }
  local callbacks = {}
  -- Rejects document type declarations before they can introduce entities.
  --@param none No arguments; this closure uses its captured fixture state.
  --@return nil No normal return.
  --@error Always raises security:dtd-forbidden.
  callbacks.StartDoctypeDecl = function()
    error("security:dtd-forbidden", 0)
  end
  -- Rejects all entity declarations.
  --@param none No arguments; this closure uses its captured fixture state.
  --@return nil No normal return.
  --@error Always raises security:entity-forbidden.
  callbacks.EntityDecl = function()
    error("security:entity-forbidden", 0)
  end
  -- Counts and rejects an external entity callback.
  --@param none No arguments; this closure uses its captured fixture state.
  --@return nil No normal return.
  --@error Always raises security:external-entity-forbidden.
  callbacks.ExternalEntityRef = function()
    state.external_calls = state.external_calls + 1
    error("security:external-entity-forbidden", 0)
  end
  -- Checks depth, element, attribute, and Context vocabulary limits on entry.
  --@param _ any Unused callback argument supplied by the port.
  --@param name string XML element name delivered by LuaExpat.
  --@param attributes table XML attributes delivered by LuaExpat.
  --@return nil No value; updates parse counters and invokes an optional observer.
  --@error Raises a limit or schema code on rejection.
  callbacks.StartElement = function(_, name, attributes)
    state.depth = state.depth + 1
    state.elements = state.elements + 1
    if state.depth > limits.depth then error("limit:depth", 0) end
    if state.elements > limits.elements then error("limit:elements", 0) end
    local count = 0
    for key in pairs(attributes) do
      if type(key) == "string" then count = count + 1 end
    end
    if count > limits.attributes then error("limit:attributes", 0) end
    if options.context_semantics and not CONTEXT_ELEMENTS[name] then
      error("schema:unknown-element:" .. name, 0)
    end
    state.names[name] = (state.names[name] or 0) + 1
    if options.on_start then options.on_start(name, attributes, state) end
  end
  -- Finishes one XML element and updates the current depth.
  --@param _ any Unused callback argument supplied by the port.
  --@param name string XML element name delivered by LuaExpat.
  --@return nil No value; invokes an optional observer and decrements depth.
  callbacks.EndElement = function(_, name)
    if options.on_end then options.on_end(name, state) end
    state.depth = state.depth - 1
  end
  -- Counts text bytes and enforces the text-size bound.
  --@param _ any Unused callback argument supplied by the port.
  --@param text string XML character-data bytes delivered by LuaExpat.
  --@return nil No value; updates text count and invokes an optional observer.
  --@error Raises limit:text when the byte bound is exceeded.
  callbacks.CharacterData = function(_, text)
    state.text_bytes = state.text_bytes + #text
    if state.text_bytes > limits.text_bytes then error("limit:text", 0) end
    if options.on_text then options.on_text(text, state) end
  end

  if #document > limits.total_bytes then return nil, "limit:total-bytes", state end
  local parser = lxp.new(callbacks, nil, true)
  for _, chunk in ipairs(chunks) do
    local call_ok, ok, parse_error = pcall(parser.parse, parser, chunk)
    if not call_ok then
      -- Closes the parser after a callback exception without hiding that exception.
      --@param none No arguments; this closure uses its captured fixture state.
      --@return nil No value; parser close errors are intentionally ignored here.
      pcall(function() parser:close() end)
      return nil, tostring(ok), state
    elseif not ok then
      -- Closes the parser after a parse failure without hiding that failure.
      --@param none No arguments; this closure uses its captured fixture state.
      --@return nil No value; parser close errors are intentionally ignored here.
      pcall(function() parser:close() end)
      return nil, tostring(parse_error), state
    end
  end
  local call_ok, ok, parse_error = pcall(parser.parse, parser)
  if not call_ok then
    -- Closes the parser after a final-chunk callback exception.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; parser close errors are intentionally ignored here.
    pcall(function() parser:close() end)
    return nil, tostring(ok), state
  elseif not ok then
    -- Closes the parser after final-chunk parse failure.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; parser close errors are intentionally ignored here.
    pcall(function() parser:close() end)
    return nil, tostring(parse_error), state
  end
  parser:close()
  return true, nil, state
end

-- Splits one byte string at a requested boundary for chunked parser tests.
--@param value string XML bytes to split.
--@param position integer Last byte included in the first chunk.
--@return table chunks Two ordered byte strings whose concatenation equals value.
local function split_at(value, position)
  return { value:sub(1, position), value:sub(position + 1) }
end

-- Renders one field carrier with its declared representation and byte count.
--@param field table Encoded field with representation, raw_bytes, and carrier.
--@return string xml Complete Field element used by the corpus.
local function field_xml(field)
  return ("<Field name=\"proof\" representation=\"%s\" rawBytes=\"%d\">%s</Field>"):format(
    field.representation,
    field.raw_bytes,
    field.carrier
  )
end

-- Parses a Field element and reconstructs its carrier bytes.
--@param document string Complete XML field element.
--@param chunks table Ordered byte chunks sent to the parser.
--@return string|nil bytes Decoded field bytes, or nil when absent or invalid.
--@return string|nil reason Parser or carrier failure when decoding fails.
local function parse_field(document, chunks)
  local representation
  local raw_bytes
  local content = {}
  local ok, parse_error = parse_document(document, chunks, {
    limits = { total_bytes = 1024 * 1024, depth = 4, elements = 2, attributes = 8, text_bytes = 1024 * 1024 },
    -- Captures the Field representation and declared raw byte count.
    --@param name string Parsed XML element name.
    --@param attributes table Attributes of the Field element.
    --@return nil No value; updates captured carrier metadata.
    --@error Raises when the element name is not Field.
    on_start = function(name, attributes)
      if name ~= "Field" then error("schema:not-field", 0) end
      representation = attributes.representation
      raw_bytes = tonumber(attributes.rawBytes)
    end,
    -- Appends parsed Field text to the carrier buffer.
    --@param text string Character-data chunk from LuaExpat.
    --@return nil No value; appends the chunk to content.
    on_text = function(text)
      content[#content + 1] = text
    end,
  })
  if not ok then return nil, parse_error end
  local carrier = table.concat(content)
  if representation == "base64" then
    carrier = assert(base64_decode(carrier))
  elseif representation ~= "text" then
    return nil, "unknown-representation"
  end
  if #carrier ~= raw_bytes then return nil, "raw-byte-count-mismatch" end
  return carrier
end

-- Requires a malicious or over-limit XML document to fail with a stable reason.
--@param label string Case name included in assertion diagnostics.
--@param document string Rejected XML bytes.
--@param expected string Required substring of the parser rejection reason.
--@return table state Parser counters, including external entity calls before rejection.
--@error Raises when the document is accepted or the rejection reason differs.
local function assert_rejected(label, document, expected)
  local ok, parse_error, state = parse_document(document, { document }, {
    context_semantics = true,
    limits = { total_bytes = 4096, depth = 32, elements = 128, attributes = 8, text_bytes = 1024 },
  })
  check(not ok, label .. " is rejected")
  check(tostring(parse_error):find(expected, 1, true) ~= nil, label .. " has stable error class")
  return state
end

check(_VERSION == "Lua 5.5", "proof runs on Lua 5.5 ABI")
check(type(lxp._VERSION) == "string" and lxp._VERSION:find("1.5.2", 1, true), "LuaExpat version is 1.5.2")
equal(lxp._EXPAT_VERSION, "expat_2.8.2", "runtime Expat version is pinned")
check(type(lxp._EXPAT_FEATURES) == "table", "Expat feature manifest is available")

local fixture = read_all(fixture_path)
local rng = read_all(rng_path)
check(#rng > 0 and rng:find("YacaContext", 1, true), "Relax NG contract is supplied to proof")

local context_splits = 0
for position = 0, #fixture do
  local ok, parse_error = parse_document(fixture, split_at(fixture, position), { context_semantics = true })
  check(ok, "context fixture parses at split " .. position .. ": " .. tostring(parse_error))
  context_splits = context_splits + 1
end
for chunk_size = 1, 31 do
  local chunks = {}
  for position = 1, #fixture, chunk_size do
    chunks[#chunks + 1] = fixture:sub(position, position + chunk_size - 1)
  end
  local ok, parse_error = parse_document(fixture, chunks, { context_semantics = true })
  check(ok, "context fixture parses with chunk size " .. chunk_size .. ": " .. tostring(parse_error))
end

local dtd_state = assert_rejected(
  "internal entity",
  '<!DOCTYPE YacaContext [<!ENTITY x "secret">]><YacaContext>&x;</YacaContext>',
  "security:dtd-forbidden"
)
equal(dtd_state.external_calls, 0, "DTD is stopped before any external entity callback")
local external_state = assert_rejected(
  "external entity",
  '<!DOCTYPE YacaContext [<!ENTITY x SYSTEM "file:///definitely-not-readable-yaca-proof">]><YacaContext>&x;</YacaContext>',
  "security:dtd-forbidden"
)
equal(external_state.external_calls, 0, "external entity is never opened")
assert_rejected(
  "entity expansion bomb",
  '<!DOCTYPE YacaContext [<!ENTITY a "1234567890"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;">]><YacaContext>&b;</YacaContext>',
  "security:dtd-forbidden"
)
assert_rejected(
  "XInclude",
  '<YacaContext xmlns:xi="http://www.w3.org/2001/XInclude"><xi:include href="file:///etc/passwd"/></YacaContext>',
  "schema:unknown-element"
)
assert_rejected("unknown element", "<YacaContext><Unknown/></YacaContext>", "schema:unknown-element")
assert_rejected("invalid UTF-8", "<YacaContext>" .. string.char(0xc0, 0xaf) .. "</YacaContext>", "not well-formed")
assert_rejected("depth limit", string.rep("<Header>", 34) .. string.rep("</Header>", 34), "limit:depth")
local attributes = {}
for index = 1, 9 do attributes[#attributes + 1] = (" a%d=\"x\""):format(index) end
assert_rejected("attribute limit", "<YacaContext" .. table.concat(attributes) .. "/>", "limit:attributes")
assert_rejected("text limit", "<YacaContext>" .. string.rep("x", 1025) .. "</YacaContext>", "limit:text")
assert_rejected("total byte limit", "<YacaContext>" .. string.rep("x", 5000) .. "</YacaContext>", "limit:total-bytes")

local missing = assert(encode_scalar(nil))
equal(missing.presence, "missing", "missing scalar preserves identity")
local empty = assert(encode_scalar(""))
equal(empty.presence, "present", "empty scalar remains present")
equal(empty.representation, "text", "empty scalar uses text representation")
equal(decode_carrier(empty), "", "empty scalar round-trips")

local binary = {}
for octet = 0, 255 do binary[#binary + 1] = string.char(octet) end
binary = table.concat(binary)
local binary_field = encode_binary(binary)
equal(decode_carrier(binary_field), binary, "all 256 byte values round-trip through binary carrier")
local binary_document = field_xml(binary_field)
for position = 0, #binary_document do
  local decoded, parse_error = parse_field(binary_document, split_at(binary_document, position))
  check(decoded ~= nil, "binary field parses at split " .. position .. ": " .. tostring(parse_error))
  equal(decoded, binary, "binary bytes match at split " .. position)
end

local scalar_count = 0
local text_count = 0
local base64_count = 0
for codepoint = 0, 0x10ffff do
  if codepoint < 0xd800 or codepoint > 0xdfff then
    local encoded = encode_codepoint(codepoint)
    local decoded, decode_error = strict_utf8_codepoints(encoded)
    check(decoded ~= nil, "encoded scalar is strict UTF-8: " .. tostring(decode_error))
    equal(#decoded, 1, "single scalar decodes once")
    equal(decoded[1], codepoint, "scalar value survives strict codec")
    local carrier, carrier_error = encode_scalar(encoded)
    check(carrier ~= nil, "valid scalar has a carrier: " .. tostring(carrier_error))
    local expected_representation = xml_text_lossless(codepoint) and "text" or "base64"
    equal(carrier.representation, expected_representation, "scalar representation is deterministic")
    if carrier.representation == "base64" then
      equal(assert(base64_decode(carrier.carrier)), encoded, "base64 scalar bytes round-trip")
      base64_count = base64_count + 1
    else
      text_count = text_count + 1
    end
    scalar_count = scalar_count + 1
  end
end
equal(scalar_count, 0x110000 - 0x800, "all Unicode scalar values are enumerated")
check(text_count > 0 and base64_count > 0, "scalar corpus exercises text and base64")

local invalid_utf8 = {
  string.char(0x80),
  string.char(0xc0, 0x80),
  string.char(0xc1, 0xbf),
  string.char(0xe0, 0x80, 0x80),
  string.char(0xed, 0xa0, 0x80),
  string.char(0xed, 0xbf, 0xbf),
  string.char(0xf0, 0x80, 0x80, 0x80),
  string.char(0xf4, 0x90, 0x80, 0x80),
  string.char(0xf5, 0x80, 0x80, 0x80),
  string.char(0xe2, 0x82),
  string.char(0xf0, 0x9f, 0x92),
  string.char(0xff),
}
for index, value in ipairs(invalid_utf8) do
  local carrier, carrier_error = encode_scalar(value)
  equal(carrier, nil, "invalid UTF-8 case " .. index .. " is rejected")
  check(carrier_error:find("invalid-scalar", 1, true) == 1, "invalid scalar error is typed")
end

local representative = {
  "ASCII",
  "中文",
  encode_codepoint(0x1f642),
  "e" .. encode_codepoint(0x301),
  encode_codepoint(0xfdd0),
  encode_codepoint(0xfeff),
  "&<>\"'\\",
  "]]>",
  "\tline one\nline two",
  "\r",
  "\r\n",
  "  leading  and  trailing  ",
  "a" .. string.char(0) .. "b",
}
local field_splits = 0
for case_index, value in ipairs(representative) do
  local encoded, encode_error = encode_scalar(value)
  check(encoded ~= nil, "representative scalar encodes: " .. tostring(encode_error))
  local document = field_xml(encoded)
  for position = 0, #document do
    local decoded, parse_error = parse_field(document, split_at(document, position))
    check(decoded ~= nil, ("representative %d parses at split %d: %s"):format(case_index, position, tostring(parse_error)))
    equal(decoded, value, ("representative %d byte equality at split %d"):format(case_index, position))
    field_splits = field_splits + 1
  end
end

local forbidden = {
  "WorkspaceRoot", "WorkspaceRoots", "Branch", "Undo", "Backup", "Restore",
  "PlanArtifact", "TelemetryReceipt", "UpdateManifest", "Image", "Audio",
  "Transcription", "Speech", "Remote", "DiagnosticUpload",
}
local zero_hits = 0
for _, token in ipairs(forbidden) do
  if fixture:find("<" .. token, 1, true) or rng:find('name="' .. token .. '"', 1, true) then
    zero_hits = zero_hits + 1
  end
end
equal(zero_hits, 0, "context fixture/schema have zero excluded elements")

print("lua_runtime=" .. _VERSION)
print("luaexpat=" .. lxp._VERSION)
print("expat=" .. lxp._EXPAT_VERSION)
print("parser=context_split_positions:" .. context_splits .. ",external_entity_callbacks:0")
print(("unicode_scalars=total:%d,text:%d,base64:%d"):format(scalar_count, text_count, base64_count))
print("binary_octets=256")
print("invalid_utf8_cases=" .. #invalid_utf8)
print("field_split_roundtrips=" .. field_splits)
print("zero_surface_hits=" .. zero_hits)
print("lua_assertions=" .. assertions)
