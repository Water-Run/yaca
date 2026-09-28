--[[
Author: WaterRun
Date: 2026-09-28
File: textcodec_test.lua
Description: Verifies encoding label normalization, code page facts, and native codec adaptation.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local textcodec = load_table("src/textcodec.lua")

--Builds a fake native text module that records conversion requests.
--@param facts table Raw facts returned by text_facts.
--@param calls table Array receiving {direction, target, bytes, lossy} records.
--@return table native Fake native module with text_facts and text_convert.
local function fake_native(facts, calls)
    return {
        --Returns the configured raw code page facts.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table facts Raw facts supplied by the case.
        text_facts = function() return facts end,
        --Records a conversion and answers from a tiny GBK table.
        --@param direction string decode or encode.
        --@param target integer|string Native code page or iconv charset.
        --@param bytes string Input bytes.
        --@param lossy boolean Whether replacement decoding was requested.
        --@return boolean ok Whether the fake conversion succeeded.
        --@return string|table output Converted bytes or typed error.
        --@return boolean exact Whether the conversion was exact.
        text_convert = function(direction, target, bytes, lossy)
            calls[#calls + 1] = { direction, target, bytes, lossy }
            if target == "NOPE" or target == 874 then
                return false, { code = "EncodingUnavailable", message = "missing" }
            end
            if direction == "decode" then
                if bytes == "\214\208" then return true, "中", true end
                if lossy then return true, "\239\191\189", false end
                return false, { code = "InvalidEncoding", message = "bad" }
            end
            if bytes == "中" then return true, "\214\208", true end
            return false, { code = "EncodingLossy", message = "unmappable" }
        end,
    }
end

return {
    name = "unit/textcodec",
    cases = {
        {
            name = "labels normalize to UTF names or supported cp numbers",
            --Verifies labels normalize to UTF names or supported cp numbers.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify the normalization table.
            run = function()
                local expected = {
                    ["UTF8"] = "utf-8", ["utf-8"] = "utf-8", ["utf-16le-bom"] = "utf-16le-bom",
                    GBK = "cp936", gb2312 = "cp936", CP936 = "cp936", GB18030 = "cp54936",
                    ["windows-1252"] = "cp1252", ["ISO-8859-1"] = "cp28591", latin1 = "cp28591",
                    ["iso8859-15"] = "cp28605", Big5 = "cp950", ["Shift_JIS"] = "cp932",
                    ["koi8-r"] = "cp20866", ibm866 = "cp866", ["euc-kr"] = "cp949",
                }
                for label, canonical in pairs(expected) do
                    A.equal(textcodec.normalize(label), canonical, label)
                end
                for _, label in ipairs({ "", "cp65001", "cp1200", "iso-2022-jp", "utf-7", "ebcdic", 12 }) do
                    local normalized, err = textcodec.normalize(label)
                    A.falsy(normalized, tostring(label))
                    A.equal(err.code, "InvalidEncoding")
                end
                A.truthy(textcodec.is_legacy("cp936"))
                A.falsy(textcodec.is_legacy("utf-8"))
            end,
        },
        {
            name = "Windows facts select ANSI for files and the console page for output",
            --Verifies Windows facts select ANSI for files and the console page for output.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify derived Windows defaults and conversions.
            run = function()
                local calls = {}
                local codec = textcodec.new(fake_native({
                    kind = "windows-codepage", ansi = 936, oem = 437, console_output = 0,
                }, calls), "windows")
                A.equal(codec.facts.ansi, "cp936")
                A.equal(codec.facts.oem, "cp437")
                A.equal(codec.facts.console_output, false)
                A.equal(codec.facts.file_default, "cp936")
                A.equal(codec.facts.output_default, "cp437")
                local decoded, exact = codec.decode("cp936", "\214\208")
                A.equal(decoded, "中"); A.equal(exact, true)
                A.deep_equal(calls[1], { "decode", 936, "\214\208", false })
                local lossy, lossy_exact = codec.decode("cp936", "\255", true)
                A.equal(lossy, "\239\191\189"); A.equal(lossy_exact, false)
                local failed, err = codec.decode("cp936", "\255")
                A.falsy(failed); A.equal(err.code, "InvalidEncoding")
                A.equal(codec.encode("cp936", "中"), "\214\208")
                local refused, refused_error = codec.encode("cp936", "😀")
                A.falsy(refused); A.equal(refused_error.code, "EncodingLossy")
                local missing, missing_error = codec.decode("cp874", "x")
                A.falsy(missing); A.equal(missing_error.code, "EncodingUnavailable")
                --Attempts to mutate the frozen facts.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil Raises before returning.
                A.raises(function() codec.facts.ansi = "cp1252" end, "cannot be modified")
            end,
        },
        {
            name = "UTF-8 Windows code pages leave no legacy default",
            --Verifies UTF-8 Windows code pages leave no legacy default.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify UTF-8 system code pages.
            run = function()
                local codec = textcodec.new(fake_native({
                    kind = "windows-codepage", ansi = 65001, oem = 65001, console_output = 65001,
                }, {}), "windows")
                A.equal(codec.facts.ansi, "utf-8")
                A.equal(codec.facts.file_default, false)
                A.equal(codec.facts.output_default, false)
            end,
        },
        {
            name = "POSIX facts come from the locale environment and map to iconv names",
            --Verifies POSIX facts come from the locale environment and map to iconv names.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify locale parsing and iconv targets.
            run = function()
                local calls = {}
                local environment = { LANG = "zh_CN.GBK" }
                local codec = textcodec.new(fake_native({ kind = "iconv" }, calls), "posix",
                    --Reads the fixture environment.
                    --@param name string Variable name.
                    --@return string|nil value Configured value.
                    function(name) return environment[name] end)
                A.equal(codec.facts.locale, "cp936")
                A.equal(codec.facts.file_default, "cp936")
                codec.decode("cp936", "\214\208")
                codec.decode("cp54936", "\214\208")
                codec.decode("cp1252", "\214\208")
                A.equal(calls[1][2], "CP936")
                A.equal(calls[2][2], "GB18030")
                A.equal(calls[3][2], "CP1252")
                local utf8_codec = textcodec.new(fake_native({ kind = "iconv" }, {}), "posix",
                    --Reads a UTF-8 locale from LC_ALL before LANG.
                    --@param name string Variable name.
                    --@return string|nil value Configured value.
                    function(name) return ({ LC_ALL = "en_US.UTF-8", LANG = "zh_CN.GBK" })[name] end)
                A.equal(utf8_codec.facts.locale, "utf-8")
                A.equal(utf8_codec.facts.file_default, false)
                local plain = textcodec.new(fake_native({ kind = "iconv" }, {}), "posix",
                    --Reads a charset-less C locale.
                    --@param name string Variable name.
                    --@return string|nil value Configured value.
                    function(name) return name == "LANG" and "C" or nil end)
                A.equal(plain.facts.locale, false)
            end,
        },
        {
            name = "POSIX legacy names preserve ISO pages and Windows Thai and Big5 variants",
            -- Keep Windows code page semantics when choosing the system iconv converter.
            --@param none Uses a recording native fixture without performing native conversion.
            --@return nil Assertions require exact iconv names for every ISO page and both Windows variants.
            run = function()
                local calls = {}
                local codec = textcodec.new(fake_native({ kind = "iconv" }, calls), "posix")
                local expected = { cp874 = "CP874", cp950 = "CP950" }
                for _, part in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 15 }) do
                    local label = assert(textcodec.normalize("iso-8859-" .. tostring(part)))
                    expected[label] = "ISO-8859-" .. tostring(part)
                end
                for label, target in pairs(expected) do
                    codec.decode(label, "\214\208")
                    A.equal(calls[#calls][2], target, label)
                end
            end,
        },
        {
            name = "missing native conversion yields no codec",
            --Verifies missing native conversion yields no codec.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify the unavailable result.
            run = function()
                A.equal(textcodec.new({}, "windows"), false)
                A.equal(textcodec.new(nil, "posix"), false)
                A.equal(textcodec.new(fake_native({}, {}), "haiku"), false)
            end,
        },
    },
}
