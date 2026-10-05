#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
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
import json
import os
import pathlib
import pty
import re
import select
import secrets
import shlex
import struct
import subprocess
import termios
import time
import tty


# Verify the latest genuine approval card binds only the authorized print-only Lua probe.
#@param transcript bytes Captured turn output; escaped model/user chrome is not an approval card.
#@return None No value; every other tool, code body, argument list or incomplete card raises AssertionError.
#@error Refuses approval before input is sent when the proposed operation differs from the probe.
def verify_lua_approval(transcript):
    plain=re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]',b'',transcript).replace(b'\r',b'')
    cards=list(re.finditer(rb'(?:^|\n)\[ACTION approval-1\]\n',plain))
    assert cards, 'the expected approval card was not displayed'
    card=plain[cards[-1].end():]
    assert re.search(rb'^tool: lua$',card,re.M), 'the pending tool is not the Lua probe'
    assert b'allow approval-1 once | deny approval-1 | details approval-1' in card
    assert re.search(rb'^default: deny$',card,re.M), 'approval card is incomplete'
    line=re.search(rb'^arguments: ([^\n]+)$',card,re.M)
    assert line, 'approval arguments are unavailable'
    try:
        arguments=json.loads(line[1].decode('utf-8'))
    except (ValueError,UnicodeError):
        raise AssertionError('approval arguments are not complete UTF-8 JSON') from None
    assert isinstance(arguments,dict) and set(arguments)<= {'code','args','cwd','deadline_ms'}
    assert arguments.get('code')=='print(6*7)', 'Lua probe code changed'
    assert arguments.get('args',[])==[], 'Lua probe acquired extra arguments'
    if 'deadline_ms' in arguments:
        assert type(arguments['deadline_ms']) is int and arguments['deadline_ms']>0


# Verify one admitted Lua execution while allowing separately identified requests that never ran.
#@param transcript bytes Trusted turn transcript collected after the explicit approval.
#@return str Display ID whose requested arguments, progress and completed outcome agree.
#@error Raises on changed code/tools, a second execution, missing proposal or split execution identity.
def verify_lua_execution(transcript):
    plain=re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]',b'',transcript).replace(b'\r',b'')
    headers=list(re.finditer(rb'(?:^|\n)\[TOOL (tool-[0-9]+)\]\n',plain))
    proposals={}
    progress=set()
    completed=[]
    for index,header in enumerate(headers):
        identity=header[1]
        end=headers[index+1].start() if index+1<len(headers) else len(plain)
        block=plain[header.end():end]
        block=re.split(rb'\n(?=\[|>>|\?\?)',block,maxsplit=1)[0]
        name=re.search(rb'^name: ([^\n]+)$',block,re.M)
        if name:
            assert name[1]==b'lua', 'the turn requested a different tool'
        arguments=re.search(rb'^arguments: ([^\n]+)$',block,re.M)
        if arguments:
            value=json.loads(arguments[1].decode('utf-8'))
            assert isinstance(value,dict) and set(value)<= {'code','args','cwd','deadline_ms'}
            assert value.get('code')=='print(6*7)' and value.get('args',[])==[], \
                'a Lua request differs from the print-only probe'
            assert identity not in proposals or proposals[identity]==value, 'tool proposal changed identity'
            proposals[identity]=value
        if re.search(rb'^(stdout|stderr): ',block,re.M):
            progress.add(identity)
        outcome=re.search(rb'^process outcome: ([^\n]+)$',block,re.M)
        if outcome:
            assert outcome[1]==b'completed', 'Lua execution did not complete'
            completed.append(identity)
    assert len(completed)==1, 'the turn did not complete exactly one Lua execution'
    identity=completed[0]
    assert identity in proposals, 'execution identity differs from its proposal'
    assert progress<= {identity}, 'execution progress acquired a different display ID'
    return identity.decode('ascii')


# Verify the restored Ask uses its durable sequence and recalls only the hidden expected token.
#@param transcript bytes One restored Ask transcript; the submitted question contains no answer token.
#@param token str Random token committed by a main turn in the earlier process.
#@return str Accepted Ask ID whose completed response consists only of token.
#@error Raises for conflicting identities, a different answer, an incomplete response or tool activity.
def verify_recalled_token(transcript,token):
    plain=re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]',b'',transcript).replace(b'\r',b'')
    identities=re.findall(rb'^Ask request accepted: (ask-[0-9]+)$',plain,re.M)
    assert len(identities)==1, 'restored Ask identity is missing or ambiguous'
    identity=identities[0]
    answer=re.search(rb'(?:^|\n)\[ASK '+identity+rb'\]\n(.*?)\n\[STATUS\]\nAsk '
                     +identity+rb' outcome: completed(?:\n|$)',plain,re.S)
    assert answer and answer[1].strip()==token.encode('utf-8'), \
        "reopened Context did not recall the earlier main turn's verification token"
    assert not re.search(rb'^\[TOOL ',plain,re.M), 'restored pure Ask invoked a tool'
    return identity.decode('ascii')


# Runs the agent terminal smoke command and reports its status.
#@param none No arguments.
#@return None result No value; assertions exercise the portable terminal interaction.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    parser.add_argument("directory", help="isolated deployment path in the SSH shell")
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("--online", action="store_true")
    parser.add_argument("--local", action="store_true", help="run an isolated local POSIX shell instead of SSH")
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
    if args.local:
        if args.executable != "yaca":
            parser.error("local PTY execution requires the Linux executable")
        command=["/bin/bash","--noprofile","--norc","-i"]
    else:
        command = ["ssh", "-tt", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                   "-p", str(args.port)]
        if args.identity:
            command.extend(("-i", str(args.identity.resolve())))
        command.append(args.host)
    platform = "windows" if args.executable.endswith(".exe") else "linux"
    child = subprocess.Popen(
        command,
        env=dict(os.environ,PS1="$ ") if args.local else None,
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
            proposal_start=len(received)
            send("Call the built-in lua tool exactly once with code print(6*7). "
                 "Report the actual result briefly, then finish. Use no other tool.")
            expect("allow approval-1 once", 180, application=True)
            expect("default: deny", 30, application=True)
            verify_lua_approval(bytes(received[proposal_start:]))
            send("allow approval-1 once")
            expect("Turn outcome: completed", 180, application=True)
            before_ask = len(received)
            send(".ask What was the numeric result? Answer with the number only.")
            expect("[ASK ask-2]", 180, application=True)
            expect("Ask ask-2 outcome: completed", 30)
            ask_transcript = bytes(received[before_ask:])
            assert re.search(rb"\[ASK ask-2\]\s+42\s", ask_transcript), "Ask result differs"
            assert b"[TOOL " not in ask_transcript, "Ask invoked a tool"
            verify_lua_execution(bytes(received[proposal_start:before_ask]))
            send(".status")
            expect("ask: idle false")
            print(platform + "-agent-lua-and-ask=PASS", flush=True)
            recall_token="yaca-memory-"+secrets.token_hex(8)
            send("Remember this verification token in this conversation: "
                 + recall_token + ". Reply with exactly STORED, then finish. Use no tools.")
            expect("Turn outcome: completed",180,application=True)
            send(".status")
            expect("[DETAILS status]",30,application=True)
            expect("ask: idle false",30,application=True)
        send(".quit")
        expect("SMOKE> ")
        send("result=$?; printf '\\nSMOKE_APP_%s:%s\\n' EXIT \"$result\"")
        expect("SMOKE_APP_EXIT:0")
        send("after=$(/usr/bin/stty -g); [ \"$before\" = \"$after\" ] "
             "&& printf '\\nSMOKE_TERMINAL_%s\\n' RESTORED")
        expect("SMOKE_TERMINAL_RESTORED")
        if args.online:
            expect("SMOKE> ",30)
            plain=re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]',b'',bytes(received)).replace(b'\r',b'')
            hashes=re.findall(rb'context hash: ([0-9A-F]{16})',plain)
            assert hashes, "durable Context identity was not displayed"
            send("cd workspace")
            expect("SMOKE> ",30)
            send("../"+args.executable+" --continue "+hashes[-1].decode('ascii'))
            expect(">>",30,application=True)
            before_recall=len(received)
            send(".ask What verification token did I ask you to remember? Reply with the exact token only.")
            expect("Ask request accepted: ",30,application=True)
            expect("\n",30,application=True)
            accepted=re.findall(rb'Ask request accepted: (ask-[0-9]+)',bytes(received[before_recall:]))
            assert len(accepted)==1, 'restored Ask acceptance is ambiguous'
            recalled_id=accepted[0].decode('ascii')
            expect("[ASK "+recalled_id+"]",180,application=True)
            expect("Ask "+recalled_id+" outcome: completed",30,application=True)
            answer=bytes(received[before_recall:])
            verify_recalled_token(answer,recall_token)
            send(".quit")
            expect("SMOKE> ",30)
            send("result=$?; printf '\\nSMOKE_REOPEN_%s:%s\\n' EXIT \"$result\"")
            expect("SMOKE_REOPEN_EXIT:0",30)
            send("after=$(/usr/bin/stty -g); [ \"$before\" = \"$after\" ] "
                 "&& printf '\\nSMOKE_REOPEN_TERMINAL_%s\\n' RESTORED")
            expect("SMOKE_REOPEN_TERMINAL_RESTORED",30)
            print(platform+"-durable-context-reopen=PASS",flush=True)
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
