--[[
File: text_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies strict UTF-8, exact byte carriers, and display isolation.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local text = load_table("src/text.lua")
local fixtures = load_table(".develope-docs/contracts/fixtures/formats.lua")

local function all_octets()
    local parts = {}
    for value = 0, 255 do parts[#parts + 1] = string.char(value) end
    return table.concat(parts)
end

return {
    name = "unit/text",
    cases = {
        {
            name = "contract UTF-8 fixtures produce strict stable results",
            run = function()
                local expected_reason = {
                    overlong = "overlong",
                    truncated = "truncated",
                    ["isolated-continuation"] = "isolated-continuation",
                    surrogate = "surrogate",
                    ["above-maximum"] = "above-maximum",
                }
                for _, case in ipairs(fixtures.utf8_cases) do
                    local valid, result = text.validate_utf8(case.bytes)
                    A.equal(valid, case.valid, case.id)
                    if case.valid then
                        A.equal(result.byte_count, #case.bytes)
                        A.falsy(result.contains_nul)
                    else
                        A.equal(result.code, "InvalidUtf8")
                        A.equal(result.reason, expected_reason[case.id])
                        A.truthy(result.offset >= 1)
                    end
                end
            end,
        },
        {
            name = "scalar boundaries round trip without normalization",
            run = function()
                local boundaries = {
                    0x00, 0x01, 0x7F, 0x80, 0x7FF, 0x800,
                    0xD7FF, 0xE000, 0xFFFD, 0xFFFF, 0x10000, 0x10FFFF,
                }
                local encoded = assert(text.encode_utf8(boundaries))
                A.deep_equal(text.decode_utf8(encoded), boundaries)
                local valid, metadata = text.validate_utf8(encoded)
                A.truthy(valid)
                A.equal(metadata.scalar_count, #boundaries)
                A.truthy(metadata.contains_nul)

                local composed = assert(text.encode_scalar(0x00E9))
                local decomposed = "e" .. assert(text.encode_scalar(0x0301))
                A.falsy(composed == decomposed)
                A.equal(assert(text.encode_utf8(text.decode_utf8(composed))), composed)
                A.equal(assert(text.encode_utf8(text.decode_utf8(decomposed))), decomposed)
            end,
        },
        {
            name = "invalid scalar forms fail with offsets and no replacement",
            run = function()
                local cases = {
                    { string.char(0xE2, 0x28, 0xA1), "invalid-continuation", 2 },
                    { string.char(0xF5, 0x80, 0x80, 0x80), "invalid-leading-byte", 1 },
                    { string.char(0xFF), "invalid-leading-byte", 1 },
                    { string.char(0xF0, 0x9F, 0x92), "truncated", 1 },
                }
                for _, case in ipairs(cases) do
                    local valid, validation_error = text.validate_utf8(case[1])
                    A.falsy(valid)
                    A.equal(validation_error.reason, case[2])
                    A.equal(validation_error.offset, case[3])
                    local decoded, decode_error = text.decode_utf8(case[1])
                    A.falsy(decoded)
                    A.equal(decode_error.reason, case[2])
                end
                for _, scalar in ipairs({ -1, 0xD800, 0xDFFF, 0x110000, 1.5 }) do
                    local encoded, encode_error = text.encode_scalar(scalar)
                    A.falsy(encoded)
                    A.equal(encode_error.code, "InvalidScalar")
                end
                local sparse, sparse_error = text.encode_utf8({ [1] = 65, [3] = 66 })
                A.falsy(sparse)
                A.equal(sparse_error.code, "InvalidScalarArray")
            end,
        },
        {
            name = "text and binary carriers preserve their exact byte domains",
            run = function()
                local canonical = "路径\r\n" .. assert(text.encode_scalar(0x1F642))
                local text_carrier = assert(text.text(canonical))
                A.equal(text_carrier.kind, "text")
                A.equal(text_carrier.byte_count, #canonical)
                A.equal(text.canonical_bytes(text_carrier), canonical)
                A.raises(function() text_carrier.bytes = "changed" end, "cannot be modified")

                local valid_nul, nul_metadata = text.validate_utf8("a\0b")
                A.truthy(valid_nul)
                A.truthy(nul_metadata.contains_nul)
                local rejected, nul_error = text.text("a\0b")
                A.falsy(rejected)
                A.equal(nul_error.code, "NulNotText")

                local octets = all_octets()
                local binary_carrier = assert(text.binary(octets))
                A.equal(binary_carrier.kind, "binary")
                A.equal(binary_carrier.byte_count, 256)
                A.equal(text.canonical_bytes(binary_carrier), octets)
                local invalid, carrier_error = text.canonical_bytes({ bytes = octets })
                A.falsy(invalid)
                A.equal(carrier_error.code, "InvalidCarrier")
            end,
        },
        {
            name = "XML carrier classification matches lossless fixture intent",
            run = function()
                for _, case in ipairs(fixtures.xml_text_cases) do
                    if case.present ~= false then
                        local kind = text.xml_carrier_kind(case.bytes)
                        local expected = case.representation == "base64" and "binary" or "text"
                        A.equal(kind, expected, case.id)
                    end
                end
                A.equal(text.xml_carrier_kind("\t\n"), "text")
                local cr_kind, cr_reason = text.xml_carrier_kind("\r")
                A.equal(cr_kind, "binary")
                A.equal(cr_reason, "carriage-return")
                local control_kind, control_reason = text.xml_carrier_kind("\1")
                A.equal(control_kind, "binary")
                A.equal(control_reason, "xml-control")
            end,
        },
        {
            name = "lossy display escapes danger without feeding back into canonical bytes",
            run = function()
                local canonical = "A路径\n\27" .. assert(text.encode_scalar(0x202E))
                local carrier = assert(text.text(canonical))
                local unicode_display = assert(text.display_lossy(carrier))
                A.equal(unicode_display, "A路径\\n\\u{001B}\\u{202E}")
                local ascii_display = assert(text.display_lossy(carrier, { ascii_only = true }))
                A.equal(
                    ascii_display,
                    "A\\u{8DEF}\\u{5F84}\\n\\u{001B}\\u{202E}"
                )
                local multiline = assert(text.display_lossy("one\ntwo", {
                    allow_newline = true,
                }))
                A.equal(multiline, "one\ntwo")
                A.equal(text.canonical_bytes(carrier), canonical)

                local binary = assert(text.binary("A\0\255"))
                A.equal(assert(text.display_lossy(binary)), "A\\x00\\xFF")
                A.equal(text.canonical_bytes(binary), "A\0\255")
                local invalid, options_error = text.display_lossy("x", { color = true })
                A.falsy(invalid)
                A.equal(options_error.code, "InvalidDisplayOptions")
            end,
        },
    },
}
