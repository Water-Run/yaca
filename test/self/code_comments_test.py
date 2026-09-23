#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: code_comments_test.py
# Description: Rejects annotation-audit blind spots using positive and deliberately incomplete source fixtures.

import importlib
import importlib.util
import pathlib
import unittest

from tree_sitter import Language, Parser


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("comment_checker", ROOT / ".tools/check_code_comments.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


# Supply a valid file header so each fixture isolates declaration coverage.
#@param language str Supported grammar name; the two C suffixes share one grammar.
#@param body str Executable fixture text; incomplete comments are intentional test data.
#@return dict The production checker's inventory for the assembled fixture.
def audit(language, body):
    suffix = {"lua": ".lua", "python": ".py", "c": ".c",
              "bash": ".sh", "powershell": ".ps1"}[language]
    name = "fixture" + suffix
    fields = "Author: WaterRun\nDate: 2026-09-23\nFile: " + name + "\nDescription: Tests declaration contracts."
    if language == "lua":
        header = "--[[\n" + fields + "\n]]\n"
    elif language == "c":
        header = "/*\n" + fields + "\n*/\n"
    elif language == "powershell":
        header = "<#\n" + fields + "\n#>\n"
    else:
        header = "".join("# " + line + "\n" for line in fields.splitlines())
    parser = Parser(Language(importlib.import_module("tree_sitter_" + language).language()))
    return CHECKER.audit_source(pathlib.Path(name), (header + body).encode(), parser)


#@class CommentAuditTests Exercises declaration discovery and rejects incomplete contracts without running fixture code.
class CommentAuditTests(unittest.TestCase):
    # Accept a correctly annotated Lua function and its exact argument order.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if a complete contract is rejected.
    def test_complete_lua_contract(self):
        result = audit("lua", """
-- Return a selected fixture value.
--@param value string Value copied into the return slot.
--@return string The supplied value.
local function identity(value) return value end
""")
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["declarations"][0]["parameters"], ["value"])

    # Require separate contracts for private, nested and anonymous Lua functions.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if any nested executable declaration escapes the audit.
    def test_nested_and_anonymous_functions_are_not_exempt(self):
        result = audit("lua", """
-- Return a fresh fixture callback.
--@param none No arguments.
--@return function Nested fixture callback.
local function outer()
    local function inner() return 1 end
    return function() return inner() end
end
""")
        self.assertEqual(len(result["declarations"]), 3)
        self.assertFalse(result["declarations"][0]["errors"])
        self.assertTrue(all(item["errors"] for item in result["declarations"][1:]))

    # Reject wrong parameter order and omission of implicit self or varargs.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if a method's actual signature is not enforced.
    def test_lua_method_and_varargs(self):
        result = audit("lua", """
-- Expose fixture arguments for signature inspection.
--@param value string First explicit argument.
--@param self table Method receiver.
--@return any Supplied arguments.
function service:accept(value, ...) return value, ... end
""")
        declaration = result["declarations"][0]
        self.assertEqual(declaration["parameters"], ["self", "value", "..."])
        self.assertTrue(any("order/names" in error for error in declaration["errors"]))

    # Check literal metafields and the inline metamethod as independent declarations.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if a missing metafield or metamethod contract is accepted.
    def test_metatable_fields_and_callbacks(self):
        result = audit("lua", """
--@metatable fixture Read-only fixture exposing one synthetic field.
--@field __index table Supplied lookup values.
local proxy = setmetatable({}, {
    __index = { value = 1 },
    __newindex = function() error("read-only") end,
})
""")
        metatable, callback = result["declarations"]
        self.assertEqual(metatable["fields"], ["__index", "__newindex"])
        self.assertTrue(any("__newindex" in error for error in metatable["errors"]))
        self.assertEqual(callback["kind"], "function")
        self.assertTrue(callback["errors"])

    # Audit separately declared metafield tables even without a setmetatable call.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if a standalone metatable definition is missed.
    def test_standalone_metatable(self):
        result = audit("lua", "local meta = { __mode = 'k', __metatable = 'locked' }")
        self.assertEqual(len(result["declarations"]), 1)
        self.assertEqual(result["declarations"][0]["fields"], ["__mode", "__metatable"])
        self.assertTrue(result["errors"])

    # Keep code-looking test data out of the executable declaration inventory.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if string contents are treated as executable code.
    def test_strings_are_data(self):
        result = audit("lua", 'local source = [[function missing(x) return x end]]')
        self.assertEqual(result["declarations"], [])
        self.assertEqual(result["errors"], [])

    # Refuse incomplete grammar instead of silently excluding malformed declarations.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if syntax damage appears to pass annotation coverage.
    def test_parse_failure_is_a_failure(self):
        result = audit("lua", "local function broken(")
        self.assertTrue(any("unparsed source" in error["message"] for error in result["errors"]))

    # Require an explicit no-argument marker and a typed return description.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if empty-signature or return omissions pass.
    def test_empty_signature_and_return_are_explicit(self):
        result = audit("lua", "-- Finish the fixture without producing data.\nlocal function stop() end")
        errors = result["declarations"][0]["errors"]
        self.assertTrue(any("@param" in error for error in errors))
        self.assertTrue(any("@return" in error for error in errors))

    # Reject a shared comment that appears to describe two same-line lambdas.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if one annotation block covers multiple callbacks.
    def test_python_lambdas_need_individual_comments(self):
        result = audit("python", """
# Return a fixture integer.
#@param none No arguments.
#@return int The synthetic integer.
callbacks = (lambda: 1, lambda: 2)
""")
        self.assertEqual(len(result["declarations"]), 2)
        self.assertTrue(any("multiple functions" in error["message"] for error in result["errors"]))

    # Preserve both conditional C branches and enumerate all members of a declaration.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if ABI normalization removes a branch or struct field.
    def test_c_platform_branches_and_type_fields(self):
        result = audit("c", """
#ifdef _WIN32
int WINAPI probe(int win) { return win; }
#else
int probe(int unix_value) { return unix_value; }
#endif
struct Pair { int first, second; };
""")
        functions = [item for item in result["declarations"] if item["kind"] == "function"]
        self.assertEqual([item["parameters"] for item in functions], [["win"], ["unix_value"]])
        structure = next(item for item in result["declarations"] if item["kind"] == "struct")
        self.assertEqual(structure["fields"], ["first", "second"])
        self.assertFalse(any("unparsed source" in error["message"] for error in result["errors"]))

    # Include C function macros and native Lua metatable bindings in the inventory.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if a macro parameter or native metatable binding is omitted.
    def test_c_macro_and_native_metatable(self):
        result = audit("c", '#define SUM(a, b) ((a) + (b))\nvoid bind(void) { luaL_newmetatable(L, "handle"); }')
        self.assertEqual(result["declarations"][0]["parameters"], ["a", "b"])
        self.assertTrue(any(item["kind"] == "metatable" for item in result["declarations"]))

    # Enforce ownership, filename and header order independently of function comments.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if a malformed header is accepted.
    def test_fixed_header_fields(self):
        path = pathlib.Path("sample.lua")
        valid = b"--[[\nAuthor: WaterRun\nDate: 2026-09-23\nFile: sample.lua\nDescription: Exercises header validation.\n]]\n"
        self.assertEqual(CHECKER.header_errors(path, valid), [])
        self.assertTrue(CHECKER.header_errors(path, valid.replace(b"sample.lua", b"wrong.lua")))
        self.assertTrue(CHECKER.header_errors(path, valid.replace(b"Author: WaterRun", b"Author: Somebody")))
        self.assertTrue(CHECKER.header_errors(path, valid.replace(b"2026-09-23", b"2999-01-01")))

    # Include executable Python inside shell heredocs and single-quoted interpreter arguments.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if either embedded callback escapes the source inventory.
    def test_shell_embedded_python(self):
        result = audit("bash", "python3 - <<'PY'\ndef missing(value): return value\nPY\npython3 -c 'def another(): pass'\n")
        self.assertEqual([item["name"] for item in result["declarations"]], ["missing", "another"])
        self.assertTrue(all(item["language"] == "python" for item in result["declarations"]))
        self.assertTrue(all(item["errors"] for item in result["declarations"]))

    # Require contracts on PowerShell anonymous script blocks and their named parameters.
    #@param self CommentAuditTests Test runner-owned assertion context.
    #@return None Assertions finish without returning data.
    #@error Raises AssertionError if script-block callbacks or their signatures are omitted.
    def test_powershell_script_blocks(self):
        result = audit("powershell", "$handler = { param($request) $request }; function probe($value) { $value }")
        self.assertEqual([item["parameters"] for item in result["declarations"]], [["$request"], ["$value"]])
        self.assertTrue(all(item["errors"] for item in result["declarations"]))


if __name__ == "__main__":
    unittest.main()
