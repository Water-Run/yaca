#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: agent_terminal_smoke.py
# Description: Exercise a deployed Windows or Linux candidate through a real SSH PTY.

"""Exercise a deployed Windows or Linux candidate through a real SSH PTY.

Uses an existing configuration only on the explicitly selected test host. Online
requests require --online. The caller supplies an isolated application directory
with a workspace child. Logs contain the test transcript, never configuration.
"""

import argparse
import errno
import fcntl
import os
import pathlib
import pty
import re
import select
import shlex
import struct
import subprocess
import termios
import time
import tty


# Runs the agent terminal smoke command and reports its status.
#@param none No arguments.
#@return None result No value; assertions exercise the portable terminal interaction.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    parser.add_argument("directory", help="isolated deployment path in the SSH shell")
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("--online", action="store_true")
    parser.add_argument("--executable", choices=("yaca.exe", "yaca"), default="yaca.exe")
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--identity", type=pathlib.Path)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("SSH port must be between 1 and 65535")
    if args.host.startswith("-") or any(c in args.host for c in "\r\n\0"):
        parser.error("host must be an SSH destination")
    root = shlex.quote(args.directory)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_bytes(b"")
    master, slave = pty.openpty()
    # Avoid a second cooked line discipline between the harness and SSH.
    tty.setraw(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    command = ["ssh", "-tt", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
               "-p", str(args.port)]
    if args.identity:
        command.extend(("-i", str(args.identity.resolve())))
    command.append(args.host)
    platform = "windows" if args.executable.endswith(".exe") else "linux"
    child = subprocess.Popen(
        command,
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        start_new_session=True,
        # Makes the PTY slave the child's controlling terminal before exec.
        #@param none No arguments.
        #@return int ioctl result; an error aborts child setup.
        preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0),
    )
    os.close(slave)
    received = bytearray()
    cursor = 0

    # Waits for the expected terminal transcript marker.
    #@param marker str Unique event marker used by recovery assertions.
    #@param timeout float Maximum wait time in seconds.
    #@param application object The application supplied to this proof operation.
    #@return None result No value; raises if the expected Agent transcript marker is absent.
    def expect(marker, timeout=30, application=False):
        nonlocal cursor
        deadline = time.monotonic() + timeout
        needle = marker.encode("utf-8")
        while True:
            location = received.find(needle, cursor)
            if location >= 0:
                cursor = location + len(needle)
                return
            if application and b"SMOKE> " in received[cursor:]:
                raise AssertionError("application exited before " + marker)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError("timeout waiting for " + marker)
            if not select.select([master], [], [], min(remaining, 0.5))[0]:
                if child.poll() is not None:
                    raise AssertionError("SSH exited before " + marker)
                continue
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b""
            if not data:
                raise AssertionError("terminal closed before " + marker)
            received.extend(data)
            if len(received) > 2 * 1024 * 1024:
                raise AssertionError("transcript exceeded its 2 MiB bound")
            args.log.write_bytes(received)

    # Sends one terminal input line to the running Agent.
    #@param line str Terminal input line sent to the Agent.
    #@return None No value; the operation updates proof state or raises on failure.
    def send(line):
        os.write(master, line.encode("utf-8") + b"\r")

    try:
        # Send separate submitted lines, just as at the user's login prompt.
        # Do not queue a compound shell program across the native PTY hand-off.
        expect("$ ")
        send("unset PROMPT_COMMAND; PS1='SMOKE> '; cd " + root)
        expect("SMOKE> ")
        send("before=$(/usr/bin/stty -g); printf '\\nSMOKE_%s\\n' READY")
        expect("SMOKE_READY")
        send("./" + args.executable + " workspace")
        expect(">>")
        send(".side obsolete")
        expect("UsageError: unknown command line")
        send(".status")
        expect("[DETAILS status]")
        expect("state: draft-ready")
        send(".help")
        expect(".ask <message>")
        send(".multiline")
        expect("Multiline input:")
        send("中文输入检查")
        send("..status")
        send(".show")
        expect("[DETAILS multiline]")
        expect("中文输入检查")
        expect(".status")
        send(".cancel")
        expect("Multiline draft discarded.")
        print(platform + "-chat-commands=PASS", flush=True)
        if args.online:
            before_first_ask = len(received)
            send(".multiline")
            expect("Multiline input:")
            send("Reply with exactly: 中文 42")
            send("This is a pure question. Use no tools.")
            send(".ask")
            expect("[ASK ask-1]", 180, application=True)
            expect("Ask ask-1 outcome: completed", 30)
            first_ask = bytes(received[before_first_ask:])
            assert re.search("\\[ASK ask-1\\]\\s+中文 42\\s".encode("utf-8"), first_ask)
            assert b"[TOOL " not in first_ask and b"Turn outcome:" not in first_ask
            print(platform + "-first-multiline-ask=PASS", flush=True)
            send("Call the built-in lua tool exactly once with code print(6*7). "
                 "Report the actual result briefly, then finish. Use no other tool.")
            expect("allow approval-1 once", 180, application=True)
            send("allow approval-1 once")
            expect("Turn outcome: completed", 180, application=True)
            before_ask = len(received)
            send(".ask What was the numeric result? Answer with the number only.")
            expect("[ASK ask-2]", 180, application=True)
            expect("Ask ask-2 outcome: completed", 30)
            ask_transcript = bytes(received[before_ask:])
            assert re.search(rb"\[ASK ask-2\]\s+42\s", ask_transcript), "Ask result differs"
            assert b"[TOOL " not in ask_transcript, "Ask invoked a tool"
            identifiers = set(re.findall(rb"\[TOOL ([^\]]+)\]", received))
            assert identifiers == {b"tool-1"}, "one call acquired multiple display IDs"
            send(".status")
            expect("ask: idle false")
            print(platform + "-agent-lua-and-ask=PASS", flush=True)
        send(".quit")
        expect("SMOKE> ")
        send("result=$?; printf '\\nSMOKE_APP_%s:%s\\n' EXIT \"$result\"")
        expect("SMOKE_APP_EXIT:0")
        send("after=$(/usr/bin/stty -g); [ \"$before\" = \"$after\" ] "
             "&& printf '\\nSMOKE_TERMINAL_%s\\n' RESTORED")
        expect("SMOKE_TERMINAL_RESTORED")
        send("exit \"$result\"")
        assert child.wait(timeout=10) == 0
        assert received.count(b"UsageError: unknown command line") == 1
        print(platform + "-terminal-restore=PASS", flush=True)
    finally:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        args.log.write_bytes(received)
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)
        os.close(master)


if __name__ == "__main__":
    main()
