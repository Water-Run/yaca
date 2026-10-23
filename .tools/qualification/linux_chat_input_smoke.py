#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-23
# File: linux_chat_input_smoke.py
# Description: Drive a real Linux chat PTY and verify default completion, editing, asynchronous draft preservation, paste and restoration with an independent screen emulator.

import argparse
import codecs
import errno
import fcntl
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import termios
import threading
import time

import pyte


# Run one isolated, credential-free PTY journey against an explicitly supplied local core.
#@param none Reads stage, new evidence path, width and terminal profile from argparse.
#@return None Returns after verified exit zero and native terminal restoration.
#@effect Creates an isolated app/workspace, starts loopback HTTP and one owned PTY child, and saves transcripts/screens.
#@error Raises on a failed assertion, timeout, output cap or dependency/setup failure; finally releases all owned handles.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, choices=(40, 80), default=80)
    parser.add_argument("--term", choices=("xterm-256color", "dumb"), default="xterm-256color")
    args = parser.parse_args()
    stage, output = args.stage.resolve(), args.output.resolve()
    output.mkdir()
    app = output / "app"
    app.mkdir()
    shutil.copy2(stage / "yaca", app / "yaca")
    # The supplied executable is a self-contained candidate; no development payload is copied.
    workspace = app / "workspace"
    workspace.mkdir()
    requests = []
    arrived, release = threading.Event(), threading.Event()

    #@class Provider Loopback-only OpenAI fixture with one externally released delayed response.
    #@field server HTTPServer Owner of the bound loopback socket; request handlers own no permanent resources.
    class Provider(BaseHTTPRequestHandler):
        # Suppress HTTP access logs that add no verification evidence.
        #@param self Provider Request handler.
        #@param format str Standard logging format, ignored.
        #@param ... object Ignored formatting arguments.
        #@return None No result or output.
        def log_message(self, format, *args):
            pass

        # Serve one no-tool Ask response after validating its actual wire request.
        #@param self Provider Active loopback handler.
        #@return None After a complete fixed SSE response or expected peer cancellation.
        #@effect Records synthetic requests, optionally waits for the test release, and writes only to this loopback connection.
        #@error Raises for unexpected tools, credentials, oversized requests or a fixture timeout.
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            assert 0 < length <= 4 * 1024 * 1024
            request = json.loads(self.rfile.read(length))
            assert not self.headers.get("Authorization") and not request.get("tools")
            requests.append(request)
            (output / ("request-%d.json" % len(requests))).write_text(
                json.dumps(request, ensure_ascii=False, indent=2), encoding="utf-8")
            if len(requests) in (1, 3):
                arrived.set()
                assert release.wait(20), "test did not release the delayed response"
            chunks = [dict(id="pty-ask", choices=[dict(index=0, delta=dict(role="assistant", content="42"), finish_reason=None)]),
                      dict(id="pty-ask", choices=[dict(index=0, delta={}, finish_reason="stop")])]
            body = ("".join("data: " + json.dumps(item) + "\n\n" for item in chunks) + "data: [DONE]\n\n").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = HTTPServer(("127.0.0.1", 0), Provider)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, args.width, 0, 0))
    original = termios.tcgetattr(slave)
    child = None
    transcript = bytearray()
    screen = pyte.Screen(args.width, 24)
    stream = pyte.Stream(screen)
    decoder = codecs.getincrementaldecoder("utf-8")("strict")

    # Drain the owned PTY once and update an independent terminal screen model.
    #@param timeout float Maximum seconds to wait for one readable output chunk.
    #@return bool True when bytes were received, false on timeout/closed PTY.
    #@effect Reads PTY output, updates screen state and writes the bounded raw transcript.
    #@error Raises for unexpected I/O errors, invalid UTF-8 or output above two MiB.
    def drain(timeout=0.05):
        if not select.select([master], [], [], timeout)[0]:
            return False
        try:
            data = os.read(master, 65536)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            data = b""
        if not data:
            return False
        transcript.extend(data)
        assert len(transcript) <= 2 * 1024 * 1024
        stream.feed(decoder.decode(data))
        (output / "transcript.bin").write_bytes(transcript)
        return True

    # Await one fresh transcript marker and consume all immediately available output.
    #@param marker str Expected visible text or control sequence.
    #@param start int Earliest raw byte offset eligible to satisfy this wait; defaults to zero.
    #@return None After the marker has arrived and the output has quiesced briefly.
    #@effect Drains PTY bytes for at most fifteen seconds.
    #@error Raises on early process exit or a missing marker.
    def expect(marker, start=0):
        deadline = time.monotonic() + 15
        while marker.encode() not in transcript[start:]:
            assert time.monotonic() < deadline, "timeout waiting for " + repr(marker)
            assert child.poll() is None, "child exited before " + repr(marker)
            drain()
        while drain(0.1):
            pass

    # Send literal bytes to the child's input without adding an implicit Enter.
    #@param data str|bytes UTF-8 text or raw key/paste bytes.
    #@return None After the PTY accepted all bytes and emitted immediate redraw output.
    #@effect Writes only this test child's PTY and drains a bounded initial output window.
    #@error Raises if the write is partial or I/O fails.
    def send(data):
        encoded = data.encode() if isinstance(data, str) else data
        assert os.write(master, encoded) == len(encoded)
        drain(0.1)

    # Verify and save the live input row and exact cursor column using the screen oracle.
    #@param name str Fixed safe evidence basename.
    #@param line str Expected displayed input row after trimming right padding.
    #@param column int Expected zero-based terminal cursor column.
    #@return None After all assertions pass and a complete screen snapshot is saved.
    #@effect Drains pending redraws and saves the independently interpreted 24-row screen.
    #@error Raises if prompt/draft/cursor alignment differs from the expectation.
    def check_screen(name, line, column):
        while drain(0.1):
            pass
        (output / (name + ".txt")).write_text("\n".join(screen.display)
            + "\ncursor=%d,%d\n" % (screen.cursor.x, screen.cursor.y), encoding="utf-8")
        assert screen.display[screen.cursor.y].rstrip() == line, repr(screen.display[screen.cursor.y])
        assert screen.cursor.x == column, (screen.cursor.x, column)

    try:
        child = subprocess.Popen([str(app / "yaca")], cwd=workspace,
            env=dict(os.environ, TERM=args.term), stdin=slave, stdout=slave, stderr=slave,
            start_new_session=True)
        for prompt, answer in (("Model name", "PtyTest"), ("Protocol (", "openai-chat"),
                ("Enable this Model?", ""), ("Endpoint:", "http://127.0.0.1:%d/chat" % server.server_port),
                ("Remote model:", "mock"), ("Context length (tokens)", "32768"),
                ("Maximum output tokens", "4096"), ("Key (hidden;", "")):
            expect(prompt)
            send(answer + "\r")
        expect("Type APPLY")
        assert not requests
        send("APPLY\r")
        expect(">> ")
        if args.term == "dumb":
            send(".status\r")
            expect("state: draft-ready")
            assert b"\x1b[?2004h" not in transcript
        else:
            expect("\x1b[?2004h")
            send(".sta\t")
            check_screen("completion", ">> .status", 10)
            send("\r")
            expect("state: draft-ready")
            send("\x1b[A")
            check_screen("history", ">> .status", 10)
            send("\x01\x0b")
            send("a中b\x1b[DX")
            check_screen("unicode-middle", ">> a中Xb", 7)
            send("\x03")
            check_screen("cancel-draft", ">>", 3)
            old_rows, old_y = list(screen.display), screen.cursor.y
            send("q" * (args.width * 3))
            while drain(0.1):
                pass
            assert screen.cursor.y == old_y and screen.cursor.x < args.width
            assert screen.display[old_y].startswith(">> <")
            assert screen.display[:old_y] == old_rows[:old_y], "long draft overwrote transcript rows"
            send("\x01")
            assert screen.cursor.x == 3
            send("\x03")
            check_screen("long-draft-cleared", ">>", 3)
            send(".ask delayed first response\r")
            assert arrived.wait(10), "Ask was not dispatched"
            send(".sta\x1b[D")
            check_screen("busy-before", ">> .sta", 6)
            release.set()
            expect("Ask ask-1 outcome: completed")
            check_screen("busy-after", ">> .sta", 6)
            send("X\x7f\x1b[F\t\r")
            expect("state: Idle")
            before = len(requests)
            send("\x1b[200~.ask pasted\n中文\x1b[201~")
            check_screen("paste-draft", ">> .ask pasted\\n中文", 20)
            assert len(requests) == before
            send("\r")
            expect("Ask ask-2 outcome: completed")
            assert "pasted\n中文" in json.dumps(requests[-1], ensure_ascii=False).replace("\\n", "\n")
            arrived.clear()
            release.clear()
            send(".ask cancel this delayed response\r")
            assert arrived.wait(10), "cancellable Ask was not dispatched"
            cancel_start = len(transcript)
            send("\x03")
            expect("cancelled", cancel_start)
            release.set()
            check_screen("cancel-request", ">>", 3)
        send(".quit\r")
        child.wait(timeout=10)
        while drain(0.1):
            pass
        assert child.returncode == 0
        assert termios.tcgetattr(slave) == original, "terminal modes were not restored"
        (output / "result.json").write_text(json.dumps({"status": "PASS", "width": args.width,
            "term": args.term, "requests": len(requests), "modes_restored": True}, indent=2) + "\n")
    finally:
        release.set()
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=5)
        (output / "final-screen.txt").write_text("\n".join(screen.display), encoding="utf-8")
        os.close(master)
        os.close(slave)
        server.shutdown()
        server.server_close()
        worker.join(5)


if __name__ == "__main__":
    main()
