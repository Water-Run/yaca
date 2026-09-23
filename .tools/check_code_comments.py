#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: check_code_comments.py
# Description: Inventories owned source declarations and rejects missing or mismatched contract comments.

"""Check the whole repository, including private helpers and anonymous callbacks.

Install .tools/comment_check_requirements.txt in a development environment.
This checker and its parsers are build tools, not yaca runtime dependencies.
"""

import argparse
import collections
import datetime
import importlib
import json
import pathlib
import re
import subprocess
import sys

from tree_sitter import Language, Parser


ROOT = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = {".lua": "lua", ".c": "c", ".h": "c", ".py": "python",
             ".sh": "bash", ".ps1": "powershell"}
FUNCTIONS = {"lua": {"function_declaration", "function_definition"},
             "c": {"function_definition", "preproc_function_def"},
             "python": {"function_definition", "lambda"},
             "bash": {"function_definition"},
             "powershell": {"function_statement", "script_block_expression"}}
TYPES = {"struct_specifier": "struct", "union_specifier": "struct",
         "enum_specifier": "enum", "class_definition": "class"}
C_ANNOTATIONS = rb"\b(?:WINAPI|NTAPI|CALLBACK|LUAMOD_API|LUA_API|LUALIB_API|__cdecl|__stdcall)\b"


# Traverse every syntax node, including nested and anonymous declarations.
#@param root Node Root of the owned source syntax tree.
#@return Iterator[Node] Nodes in source order; comment and string nodes remain distinguishable.
def walk(root):
    pending = [root]
    while pending:
        node = pending.pop()
        yield node
        pending.extend(reversed(node.children))


# Decode one source span without changing byte offsets used by the parser.
#@param source bytes Original UTF-8 source bytes.
#@param node Node|None Selected syntax span, or None for an absent field.
#@return str Exact span text; absent fields become an empty string.
def spelling(source, node):
    return source[node.start_byte:node.end_byte].decode("utf-8") if node else ""


# Preserve line and byte positions while removing an ABI or directive token.
#@param match re.Match[bytes] Token selected by the C normalization patterns.
#@return bytes Equal-length whitespace with original newlines retained.
def whitespace(match):
    return bytes(10 if byte == 10 else 32 for byte in match[0])


# Prepare C for structural parsing while retaining declarations from every platform branch.
#@param source bytes Original UTF-8 source.
#@param language str Selected grammar name.
#@return bytes Position-preserving parser input; non-C inputs remain unchanged.
def parser_input(source, language):
    if language != "c":
        return source
    source = re.sub(C_ANNOTATIONS, whitespace, source)
    # All conditional branches remain present. A resulting grammar ambiguity
    # is reported as a parse failure; it never silently exempts a declaration.
    return re.sub(rb"(?m)^[ \t]*#(?:if[^\n]*|else[^\n]*|elif[^\n]*|endif[^\n]*)", whitespace, source)


# List all maintained source paths, including newly created files not yet staged.
#@param none No arguments.
#@return list[Path] Existing owned source files in deterministic repository-relative order.
#@effect Runs read-only Git inventory; ignored build outputs are supplied by their maintained sources.
def source_paths():
    result = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT)
    paths = sorted(set(pathlib.Path(name) for name in result.decode("utf-8").split("\0") if name))
    return [path for path in paths if path.suffix in LANGUAGES and (ROOT / path).is_file()]


# Validate fixed file-header fields before the first executable statement.
#@param path Path Repository-relative source path.
#@param source bytes Original UTF-8 source.
#@return list[str] Header violations; an empty list means the header conforms.
def header_errors(path, source):
    text = source.decode("utf-8")
    if text.startswith("#!"):
        text = text.partition("\n")[2]
    if path.suffix == ".py" and re.match(r"#.*coding[:=]", text):
        text = text.partition("\n")[2]
    if path.suffix == ".lua":
        match = re.match(r"--\[\[\n(.*?)\n\]\]", text, re.S)
    elif path.suffix in {".c", ".h"}:
        match = re.match(r"/\*\n(.*?)\n\*/", text, re.S)
    elif path.suffix == ".ps1":
        match = re.match(r"<#\n(.*?)\n#>", text, re.S)
    else:
        match = re.match(r"((?:#[^\n]*\n){4,})", text)
    if not match:
        return ["missing fixed file header"]
    lines = [re.sub(r"^[#* ]*", "", line) for line in match[1].splitlines()]
    expected = ["Author: WaterRun", "Date: ", "File: " + path.name, "Description: "]
    if len(lines) < 4 or any(not lines[index].startswith(value) for index, value in enumerate(expected)):
        return ["header must contain Author, Date, File, Description in that order"]
    problems = []
    if lines[0] != expected[0] or lines[2] != expected[2]:
        problems.append("header author or filename does not match")
    try:
        date = datetime.date.fromisoformat(lines[1][6:])
        if date.isoformat() != lines[1][6:] or date > datetime.date.today():
            problems.append("header date must be canonical and not in the future")
    except ValueError:
        problems.append("invalid header date")
    if not lines[3][13:].strip():
        problems.append("empty file description")
    return problems


# Find the declaration's preceding-comment anchor, including inline callbacks.
#@param node Node Function, type or metatable syntax node.
#@return Node Nearest enclosing declaration or expression beginning on the same source line.
def anchor(node):
    current = node
    while current.parent and current.parent.type not in {
        "chunk", "module", "translation_unit", "program", "block", "compound_statement",
        "function_declaration", "function_definition", "lambda", "table_constructor",
        "field_declaration_list", "class_body", "statement_block",
    }:
        parent = current.parent
        if parent.type == "decorated_definition" or parent.start_point.row == node.start_point.row:
            current = parent
        else:
            break
    return current


# Collect only the contiguous comment block immediately before a declaration.
#@param source bytes Original source.
#@param node Node Declaration whose contract is required.
#@param comments list[Node] Comment spans from the syntax tree.
#@return tuple[str,int] Comment text and unique start offset, or empty text and -1.
def documentation(source, node, comments):
    start = anchor(node).start_byte
    selected = []
    for comment in reversed(comments):
        if comment.end_byte > start:
            continue
        if source[comment.end_byte:start].strip():
            break
        selected.append(comment)
        start = comment.start_byte
    if not selected:
        # Python docstrings belong to the function itself, including methods.
        if node.type in {"function_definition", "class_definition"}:
            body = node.child_by_field_name("body")
            first = body.named_children[0] if body and body.named_children else None
            if first and first.type == "expression_statement" and first.named_children[0].type == "string":
                return spelling(source, first), first.start_byte
        return "", -1
    return source[start:selected[0].end_byte].decode("utf-8"), start


# Extract the name nested inside a C pointer, array or function declarator.
#@param node Node|None C declarator node.
#@param source bytes Original source bytes.
#@return str Named identifier, or empty text for an unnamed parameter.
def c_name(node, source):
    if not node:
        return ""
    if node.type in {"identifier", "field_identifier", "type_identifier"}:
        return spelling(source, node)
    child = node.child_by_field_name("declarator")
    if child:
        return c_name(child, source)
    for child in node.named_children:
        value = c_name(child, source)
        if value:
            return value
    return ""


# Read every formal parameter in source order, including varargs and implicit Lua self.
#@param node Node Function or callback declaration.
#@param source bytes Original source bytes.
#@param language str Parser grammar name.
#@return list[str]|None Parameter names; None denotes shell positional semantics checked by Review.
def parameters(node, source, language):
    if language == "bash":
        return None
    if language == "powershell":
        pending = list(reversed(node.named_children))
        while pending:
            child = pending.pop()
            if child.type in {"function_statement", "script_block_expression"}:
                continue
            if child.type in {"param_block", "function_parameter_declaration"}:
                names = []
                for parameter in walk(child):
                    if parameter.type == "script_parameter":
                        variable = next((value for value in parameter.named_children if value.type == "variable"), None)
                        names.append(spelling(source, variable))
                return names
            pending.extend(reversed(child.named_children))
        return []
    declaration = node
    if language == "c" and node.type == "function_definition":
        declaration = node.child_by_field_name("declarator")
        while declaration and declaration.type != "function_declarator":
            declaration = declaration.child_by_field_name("declarator")
    values = declaration.child_by_field_name("parameters") if declaration else None
    result = []
    if language == "lua" and ":" in spelling(source, node.child_by_field_name("name")):
        result.append("self")
    for child in values.named_children if values else []:
        if child.type in {"comment", "keyword_separator", "positional_separator"}:
            continue
        if child.type in {"vararg_expression", "variadic_parameter"}:
            result.append("...")
        elif child.type == "identifier":
            result.append(spelling(source, child))
        elif language == "c":
            if spelling(source, child).strip() != "void":
                result.append(c_name(child.child_by_field_name("declarator"), source) or "arg" + str(len(result) + 1))
        else:
            name = child.child_by_field_name("name")
            if not name:
                names = [item for item in walk(child) if item.type == "identifier"]
                name = names[0] if names else None
            result.append(spelling(source, name))
    return result


# Classify executable declarations and metatable bindings without matching strings as code.
#@param node Node Syntax node to classify.
#@param source bytes Original source bytes.
#@param language str Parser grammar name.
#@return str|None Contract kind, or None for ordinary expressions and data.
def declaration_kind(node, source, language):
    if not node.is_named:
        return None
    if node.type in FUNCTIONS[language]:
        return "function"
    if node.type in TYPES and node.child_by_field_name("body"):
        return TYPES[node.type]
    if language == "c" and node.type == "function_declarator":
        parent = node.parent
        while parent and parent.type not in {"function_definition", "declaration", "field_declaration", "type_definition"}:
            parent = parent.parent
        if parent and parent.type != "function_definition":
            return "callback"
    if language == "c" and node.type == "call_expression":
        if spelling(source, node.child_by_field_name("function")) in {
            "luaL_newmetatable", "luaL_setmetatable", "lua_setmetatable",
        }:
            return "metatable"
    if language == "lua" and node.type == "function_call":
        if spelling(source, node.child_by_field_name("name")) in {"setmetatable", "debug.setmetatable"}:
            return "metatable"
    if language == "lua" and node.type == "table_constructor":
        # Inline setmetatable arguments are covered by that binding's contract.
        if node.parent and node.parent.type == "arguments":
            call = node.parent.parent
            if call and declaration_kind(call, source, language) == "metatable":
                return None
        for field in node.named_children:
            if spelling(source, field.child_by_field_name("name")) in {
                "__index", "__newindex", "__mode", "__gc", "__close", "__metatable",
                "__pairs", "__len", "__call", "__tostring", "__name", "__add", "__sub",
                "__mul", "__mod", "__pow", "__div", "__idiv", "__band", "__bor", "__bxor",
                "__shl", "__shr", "__unm", "__bnot", "__eq", "__lt", "__le", "__concat",
            }:
                return "metatable"
    return None


# Check one declaration's markers against its actual signature.
#@param kind str Contract category.
#@param params list[str]|None Formal parameters, with None for positional shell signatures.
#@param doc str Adjacent documentation block.
#@return list[str] Missing or mismatched contract details requiring correction.
def contract_errors(kind, params, doc):
    errors = []
    if kind in {"function", "callback"}:
        documented = re.findall(r"@param\s+(\S+)", doc)
        if not documented:
            errors.append("missing @param (use none for an empty signature)")
        elif params is not None and documented != (params or ["none"]):
            errors.append("@param order/names must be " + repr(params or ["none"]))
        if not re.search(r"@return\s+\S+\s+\S", doc):
            errors.append("missing typed @return and its meaning")
        for line in doc.splitlines():
            if "@param" in line and not re.search(r"@param\s+(?:none\s+\S|\S+\s+\S+\s+\S)", line):
                errors.append("@param needs a type and specific meaning")
    elif not re.search(r"@" + kind + r"\s+\S+\s+\S", doc):
        errors.append("missing @" + kind + " name and contract")
    description = re.sub(r"^[\s#*/-]*@[^\n]*", "", doc, flags=re.M)
    if kind in {"function", "callback"} and not re.search(r"[A-Za-z\u4e00-\u9fff]", description):
        errors.append("missing function purpose")
    return errors


# Enumerate statically declared fields without guessing the shape of referenced values.
#@param node Node Metatable constructor, binding or C type declaration.
#@param source bytes Original source bytes used for field names.
#@param language str Parser grammar name.
#@return list[str] Literal field names in declaration order; referenced shapes need semantic Review.
def declared_fields(node, source, language):
    if language == "lua":
        table = node
        if node.type == "function_call":
            arguments = node.child_by_field_name("arguments")
            values = [value for value in arguments.named_children if value.type != "comment"] if arguments else []
            table = values[1] if len(values) > 1 else None
        if not table or table.type != "table_constructor":
            return []
        names = []
        for field in table.named_children:
            name = field.child_by_field_name("name")
            if name and name.type == "identifier":
                names.append(spelling(source, name))
            elif name and name.type == "string":
                # Metafield names are ASCII; escape-computed keys require Review.
                literal = spelling(source, name)
                if re.fullmatch(r'''["'][A-Za-z_][A-Za-z_0-9]*["']''', literal):
                    names.append(literal[1:-1])
        return names
    if language == "c" and node.type in {"struct_specifier", "union_specifier", "enum_specifier"}:
        body = node.child_by_field_name("body")
        names = []
        for field in body.named_children if body else []:
            if field.type == "enumerator":
                names.append(spelling(source, field.child_by_field_name("name")))
            elif field.type == "field_declaration":
                for declarator in field.children_by_field_name("declarator"):
                    name = c_name(declarator, source)
                    if name:
                        names.append(name)
        return names
    return []


# Require each statically visible type or metatable field to have its own typed contract.
#@param fields list[str] Declared field names, including every comma-separated C declarator.
#@param doc str Adjacent type or metatable documentation.
#@return list[str] Missing, duplicated or incomplete field annotations.
def field_errors(fields, doc):
    errors = []
    markers = re.findall(r"@field\s+(\S+)([^\n]*)", doc)
    counts = collections.Counter(name for name, _ in markers)
    for field in fields:
        if counts[field] != 1:
            errors.append("@field must document " + field + " exactly once")
    for name, content in markers:
        if len(content.split()) < 2:
            errors.append("@field " + name + " needs a type and specific meaning")
    return errors


# Locate executable interpreter input embedded in shell heredocs or literal -c/-e arguments.
#@param source bytes Original shell source with byte positions preserved.
#@param nodes list[Node] Complete shell syntax inventory.
#@return list[tuple[str,bytes,int]] Grammar, executable bytes and zero-based source line for each input.
def shell_sources(source, nodes):
    embedded = []
    for node in nodes:
        if node.type != "command":
            continue
        name = spelling(source, node.child_by_field_name("name")).strip("\"'").rsplit("/", 1)[-1]
        if re.fullmatch(r"python(?:[23](?:\.\d+)?)?", name):
            language, flag = "python", "-c"
        elif re.fullmatch(r"lua(?:5\.?[1-5])?", name):
            language, flag = "lua", "-e"
        elif name in {"bash", "sh"}:
            language, flag = "bash", "-c"
        else:
            continue
        parent = node.parent
        if parent and parent.type == "redirected_statement":
            for redirect in parent.named_children:
                if redirect.type == "heredoc_redirect":
                    for body in redirect.named_children:
                        if body.type == "heredoc_body":
                            embedded.append((language, source[body.start_byte:body.end_byte], body.start_point.row))
        arguments = node.children_by_field_name("argument")
        for index, argument in enumerate(arguments[:-1]):
            if spelling(source, argument) != flag:
                continue
            literal = arguments[index + 1]
            # A single-quoted shell string preserves every payload byte. Dynamic
            # expansion is not guessed; its generated-source owner needs Review.
            if literal.type == "raw_string":
                embedded.append((language, source[literal.start_byte + 1:literal.end_byte - 1], literal.start_point.row))
    return embedded


# Audit source bytes so regression fixtures use the same path as repository files.
#@param path Path Source name used for header validation and diagnostic labels.
#@param source bytes Original UTF-8 source, including its file header.
#@param parser Parser Grammar selected for the source suffix.
#@param language str|None Grammar override for interpreter source embedded in another language.
#@param check_header bool Whether to require a separate file header; embedded snippets inherit their container's header.
#@return dict Complete declaration inventory and actionable violations.
def audit_source(path, source, parser, language=None, check_header=True):
    language = language or LANGUAGES[path.suffix]
    result = {"path": path.as_posix(), "declarations": [], "errors": []}
    for error in header_errors(path, source) if check_header else []:
        result["errors"].append({"line": 1, "message": error})
    tree = parser.parse(parser_input(source, language))
    nodes = list(walk(tree.root_node))
    comments = [node for node in nodes if node.type in {"comment", "block_comment"}]
    used = set()
    for node in nodes:
        if node.is_error or node.is_missing:
            result["errors"].append({"line": node.start_point.row + 1, "message": "unparsed source: " + node.type})
        kind = declaration_kind(node, source, language)
        if not kind:
            continue
        doc, offset = documentation(source, node, comments)
        params = parameters(node, source, language) if kind in {"function", "callback"} else None
        fields = declared_fields(node, source, language) if kind not in {"function", "callback"} else []
        errors = contract_errors(kind, params, doc) + field_errors(fields, doc)
        if kind in {"function", "callback"} and offset >= 0:
            if offset in used:
                errors.append("one comment block cannot document multiple functions")
            used.add(offset)
        record = {"kind": kind, "line": node.start_point.row + 1,
                  "name": spelling(source, node.child_by_field_name("name")),
                  "parameters": params, "fields": fields, "errors": errors}
        result["declarations"].append(record)
        for error in errors:
            result["errors"].append({"line": record["line"], "message": kind + ": " + error})
    if language == "bash":
        for embedded_language, body, line_offset in shell_sources(source, nodes):
            grammar = importlib.import_module("tree_sitter_" + embedded_language)
            embedded_parser = Parser(Language(grammar.language()))
            report = audit_source(path, body, embedded_parser, embedded_language, False)
            for declaration in report["declarations"]:
                declaration["line"] += line_offset
                declaration["language"] = embedded_language
                result["declarations"].append(declaration)
            for error in report["errors"]:
                error["line"] += line_offset
                error["message"] = "embedded " + embedded_language + ": " + error["message"]
                result["errors"].append(error)
    return result


# Audit a file without accepting parse errors as an implicit exemption.
#@param path Path Repository-relative source path.
#@param parser Parser Grammar selected for the file suffix.
#@return dict Source inventory and all actionable violations for this file.
#@effect Reads the source; never rewrites it.
def audit_file(path, parser):
    return audit_source(path, (ROOT / path).read_bytes(), parser)


# Run the complete inventory and fail when any owned source violates the standard.
#@param none CLI arguments come from argparse and do not limit the repository scope.
#@return int Zero only when every parsed file and declaration passes; otherwise one.
#@effect Reads Git/source files, writes the optional JSON report, and prints violations.
def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("--inventory", type=pathlib.Path, help="write complete JSON inventory")
    arguments.add_argument("--summary-only", action="store_true", help="omit individual diagnostics, preserving failure status")
    args = arguments.parse_args()
    parsers = {}
    for name in set(LANGUAGES.values()):
        grammar = importlib.import_module("tree_sitter_" + name)
        parsers[name] = Parser(Language(grammar.language()))
    reports = [audit_file(path, parsers[LANGUAGES[path.suffix]]) for path in source_paths()]
    totals = collections.Counter()
    failures = 0
    for report in reports:
        for declaration in report["declarations"]:
            totals[declaration["kind"]] += 1
        failures += len(report["errors"])
        if not args.summary_only:
            for error in report["errors"]:
                print("%s:%d: %s" % (report["path"], error["line"], error["message"]))
    if args.inventory:
        args.inventory.write_text(json.dumps({"files": reports, "totals": dict(totals),
                                             "failures": failures}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("comment coverage: files=%d declarations=%d violations=%d %s" % (
        len(reports), sum(totals.values()), failures, "PASS" if not failures else "FAIL"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
