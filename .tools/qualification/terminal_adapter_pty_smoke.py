#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-08
# File: terminal_adapter_pty_smoke.py
# Description: Runs production Lua/native adapter recovery on independent Linux
# PTYs, verifies actual mode/descriptor restoration around injected forwarding
# rejections, and preserves every raw process transcript in a new output tree.

import argparse
import fcntl
from pathlib import Path
import os
import pty
import select
import subprocess
import termios


# Run one bounded owned PTY profile and verify kernel state before/after actual close recovery.
#@param root Path Repository or frozen input root containing the production Lua sources.
#@param interpreter Path Actual 64-bit Lua interpreter compatible with the supplied native module.
#@param library Path Existing native shared object; no module is downloaded or substituted.
#@param output Path New profile directory receiving a raw log and a private acknowledgment file.
#@param profile str Fixed close/both/joined/recover/created lifecycle scenario.
#@return None Returns only after process success and exact terminal/descriptor restoration.
#@effect Creates/closes one PTY pair, starts/joins one Lua process and writes its owned transcript.
#@error Raises on timeout or mismatched state; stops only its own child and preserves all observed output.
def run_profile(root, interpreter, library, output, profile):
    output.mkdir()
    master, slave = pty.openpty()
    original = termios.tcgetattr(slave)
    original_flags = fcntl.fcntl(slave, fcntl.F_GETFL)
    acknowledgment = output / "ack"
    child = None
    transcript = b""
    try:
        child = subprocess.Popen([str(interpreter),
            str(root / ".tools/qualification/terminal_adapter_native_smoke.lua"),
            str(root), str(library), str(acknowledgment), profile],
            stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert child.stdout is not None
        readable, _, _ = select.select([child.stdout], [], [], 10)
        assert readable, "native adapter checkpoint timeout"
        first = child.stdout.readline()
        transcript += first
        expected = b"raw" if profile in ("both", "joined") else b"restored"
        assert first == b"terminal-adapter-stage=" + expected + b"\n", first
        observed = termios.tcgetattr(slave)
        if expected == b"raw":
            assert not observed[3] & (termios.ECHO | termios.ICANON)
            assert fcntl.fcntl(slave, fcntl.F_GETFL) & os.O_NONBLOCK
        else:
            assert observed == original
            assert fcntl.fcntl(slave, fcntl.F_GETFL) == original_flags
        acknowledgment.write_bytes(b"continue\n")
        tail, _ = child.communicate(timeout=10)
        transcript += tail
        assert child.returncode == 0, transcript
        assert b"result=PASS" in tail
        assert termios.tcgetattr(slave) == original
        assert fcntl.fcntl(slave, fcntl.F_GETFL) == original_flags
    finally:
        if child is not None and child.poll() is None:
            child.kill()
            tail, _ = child.communicate(timeout=5)
            transcript += tail
        (output / "process.log").write_bytes(transcript)
        os.close(slave)
        os.close(master)


# Execute the five fixed production/native PTY profiles using an explicit new evidence directory.
#@param none Reads interpreter/library/root/output arguments from argparse.
#@return int Zero after every bounded recovery and kernel-state check passes.
#@effect Creates the output tree and serially runs only the explicitly named owned Lua fixtures.
#@error Raises for an existing destination, missing inputs or any failed profile; keeps raw evidence.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("interpreter", type=Path)
    parser.add_argument("library", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    interpreter = args.interpreter.resolve(strict=True)
    library = args.library.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir()
    for profile in ("both", "close", "joined", "recover", "created"):
        run_profile(root, interpreter, library, output / profile, profile)
        print("terminal-adapter-pty profile=" + profile + " kernel-mode-and-flags-restored=PASS", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
