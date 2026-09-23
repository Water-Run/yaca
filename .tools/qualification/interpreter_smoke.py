#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: interpreter_smoke.py
# Description: Exercise the shipped executable's Lua entry without configuration or a TTY.

"""Exercise the shipped executable's Lua entry without configuration or a TTY."""

import os
import pathlib
import subprocess
import sys
import tempfile


# Runs the interpreter smoke command and reports its status.
#@param none No arguments.
#@return None result No value; assertions cover the embedded interpreter CLI.
def main():
    executable = str(pathlib.Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="yaca lua ") as temporary:
        root = pathlib.Path(temporary)
        (root / "sample.lua").write_text(
            'assert(arg[1] == "a b" and arg[2] == "" and arg[3] == "--version")\n'
            'assert(select("#", ...) == 3)\n'
            'assert(package.loaded.main == nil and package.loaded.config == nil)\n'
            'assert(require("local_sample").value == 42)\n'
            'print("script-ok")\n', encoding="utf-8")
        (root / "local_sample.lua").write_text("return {value=42}\n", encoding="utf-8")
        environment = dict(os.environ, LUA_INIT="error('ambient init was executed')",
                           LUA_INIT_5_5="error('versioned ambient init was executed')")

        # Runs the selected command and checks its expected output.
        #@param arguments list[str] Argument vector for the child command.
        #@param expected object Expected observation or child exit state.
        #@param stdin object The stdin supplied to this proof operation.
        #@return str output Combined standard output and error from the Lua invocation.
        def run(arguments, expected=0, stdin=None):
            result = subprocess.run([executable, "--lua", "-E"] + arguments,
                                    input=stdin, capture_output=True, text=True,
                                    cwd=root, env=environment, timeout=15)
            assert result.returncode == expected, (arguments, result.returncode,
                                                    result.stdout, result.stderr)
            return result.stdout + result.stderr

        assert "Lua 5.5.1" in run(["-v"])
        assert "script-ok" in run(["sample.lua", "a b", "", "--version"])
        assert "42" in run(["-e", "print(6*7)"])
        assert "stdin-ok" in run(["-"], stdin='print("stdin-ok")\n')
        run(["-e", "os.exit(37)"], expected=37)
        assert "expected" in run(["-e", "local ="], expected=1)
        assert "sample-failure" in run(["-e", "error('sample-failure')"], expected=1)
        run(["missing.lua"], expected=1)
        assert not (root / "__yaca__").exists()
    print("embedded-lua=PASS version=5.5.1 cases=8")


if __name__ == "__main__":
    main()
