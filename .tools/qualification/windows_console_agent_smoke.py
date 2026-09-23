#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-09-23
# File: windows_console_agent_smoke.py
# Description: Native Windows console journey with an in-process, credential-free mock API.

"""Native Windows console journey with an in-process, credential-free mock API.

Supply a new candidate directory containing only yaca.exe. Tests first setup,
pure Ask, persistence/reopen and console mode restoration. No real model is used.
Run with Python 2.7 or 3 on the target Windows machine.
"""
from __future__ import print_function
import argparse
import ctypes as C
from ctypes import wintypes as W
import json
import os
import re
import subprocess
import threading
import time
try:
    from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
except ImportError:
    from http.server import HTTPServer, BaseHTTPRequestHandler
try:
    text_type = unicode
except NameError:
    text_type = str


#@class COORD Owns the windows console agent smoke state and its resource lifetime.
class COORD(C.Structure):
    _fields_ = [('x', W.SHORT), ('y', W.SHORT)]
#@class RECT Owns the windows console agent smoke state and its resource lifetime.
class RECT(C.Structure):
    _fields_ = [(name, W.SHORT) for name in ('left', 'top', 'right', 'bottom')]
#@class SCREEN Owns the windows console agent smoke state and its resource lifetime.
class SCREEN(C.Structure):
    _fields_ = [('size', COORD), ('cursor', COORD), ('attributes', W.WORD),
                ('window', RECT), ('maximum', COORD)]
#@class STARTUP Owns the windows console agent smoke state and its resource lifetime.
class STARTUP(C.Structure):
    _fields_ = [('cb', W.DWORD), ('reserved', W.LPWSTR), ('desktop', W.LPWSTR),
        ('title', W.LPWSTR)] + [(name, W.DWORD) for name in
        ('x', 'y', 'width', 'height', 'columns', 'rows', 'fill', 'flags')] + [
        ('show', W.WORD), ('reserved_size', W.WORD), ('reserved_bytes', C.c_void_p),
        ('input', W.HANDLE), ('output', W.HANDLE), ('error', W.HANDLE)]
#@class PROCESS Owns the windows console agent smoke state and its resource lifetime.
class PROCESS(C.Structure):
    _fields_ = [('process', W.HANDLE), ('thread', W.HANDLE), ('pid', W.DWORD), ('tid', W.DWORD)]
#@class CHARACTER Owns the windows console agent smoke state and its resource lifetime.
class CHARACTER(C.Union):
    _fields_ = [('unicode', W.WCHAR), ('ascii', C.c_char)]
#@class KEY Owns the windows console agent smoke state and its resource lifetime.
class KEY(C.Structure):
    _fields_ = [('down', W.BOOL), ('repeat', W.WORD), ('key', W.WORD),
        ('scan', W.WORD), ('character', CHARACTER), ('control', W.DWORD)]
#@class EVENT Owns the windows console agent smoke state and its resource lifetime.
class EVENT(C.Union):
    _fields_ = [('key', KEY), ('padding', C.c_byte * 16)]
#@class INPUT Owns the windows console agent smoke state and its resource lifetime.
class INPUT(C.Structure):
    _fields_ = [('type', W.WORD), ('event', EVENT)]


# Runs the windows console agent smoke command and reports its status.
#@param none No arguments.
#@return None result No value; assertions cover the real Windows console Agent journey.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    parser.add_argument('evidence')
    args = parser.parse_args()
    root = os.path.abspath(args.directory)
    if not isinstance(root, text_type): root = root.decode('mbcs')
    evidence = os.path.abspath(args.evidence)
    assert not os.path.exists(evidence), 'evidence directory must be new'
    os.mkdir(evidence)
    assert not os.path.exists(os.path.join(root, '__yaca__')), 'candidate must be unconfigured'
    os.mkdir(os.path.join(root, 'workspace'))
    kernel = C.windll.kernel32
    kernel.SetErrorMode(3)
    kernel.CreateFileW.restype = W.HANDLE
    kernel.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, C.c_void_p,
        W.DWORD, W.DWORD, W.HANDLE]
    kernel.CreateProcessW.argtypes = [W.LPCWSTR, W.LPWSTR, C.c_void_p, C.c_void_p,
        W.BOOL, W.DWORD, C.c_void_p, W.LPCWSTR, C.POINTER(STARTUP), C.POINTER(PROCESS)]
    kernel.CloseHandle.argtypes = [W.HANDLE]
    kernel.GetConsoleMode.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
    kernel.GetConsoleScreenBufferInfo.argtypes = [W.HANDLE, C.POINTER(SCREEN)]
    kernel.ReadConsoleOutputCharacterW.argtypes = [W.HANDLE, W.LPWSTR, W.DWORD, COORD, C.POINTER(W.DWORD)]
    kernel.WriteConsoleInputW.argtypes = [W.HANDLE, C.POINTER(INPUT), W.DWORD, C.POINTER(W.DWORD)]
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    kernel.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
    kernel.ResumeThread.argtypes = [W.HANDLE]
    kernel.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
    requests = []

    #@class Provider Owns the windows console agent smoke state and its resource lifetime.
    class Provider(BaseHTTPRequestHandler):
        # Suppresses default proof-server request logging.
        #@param self Provider Owner of the proof fixture and its resources.
        #@param unused object The unused supplied to this proof operation.
        #@return None No value; the operation updates proof state or raises on failure.
        def log_message(self, *unused): pass
        # Handles a proof HTTP POST and records its request evidence.
        #@param self Provider Owner of the proof fixture and its resources.
        #@return None No value; the operation updates proof state or raises on failure.
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            assert 0 < length <= 4 * 1024 * 1024
            request = json.loads(self.rfile.read(length).decode('utf-8'))
            assert not self.headers.get('Authorization'), 'no test credentials are permitted'
            assert not request.get('tools'), 'pure Ask advertised tools'
            requests.append(request)
            with open(os.path.join(evidence, 'request-%d.json' % len(requests)), 'wb') as stream:
                stream.write(json.dumps(request, ensure_ascii=False).encode('utf-8'))
            if request.get('stream'):
                chunks = [dict(id='console-ask', choices=[dict(index=0,
                    delta=dict(role='assistant', content='42'), finish_reason=None)]),
                    dict(id='console-ask', choices=[dict(index=0, delta={}, finish_reason='stop')])]
                body = ''.join('data: ' + json.dumps(item) + '\n\n' for item in chunks) + 'data: [DONE]\n\n'
                content_type = 'text/event-stream'
            else:
                body = json.dumps(dict(id='console-ask', choices=[dict(index=0,
                    message=dict(role='assistant', content='42'), finish_reason='stop')]))
                content_type = 'application/json'
            body = body.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = HTTPServer(('127.0.0.1', 0), Provider)
    thread = threading.Thread(target=server.serve_forever)
    thread.daemon = True
    thread.start()

    #@class Console Owns the windows console agent smoke state and its resource lifetime.
    class Console:
        # Checks   init   in windows console agent smoke.
        #@param self Console Owner of the proof fixture and its resources.
        #@param arguments list[str] Argument vector for the child command.
        #@param name str Selected fixture, component, or tool name.
        #@return None result No value; creates and owns the console child process.
        def __init__(self, arguments, name):
            self.name, self.input, self.output = name, None, None
            self.process = PROCESS()
            startup = STARTUP(); startup.cb = C.sizeof(startup)
            command = C.create_unicode_buffer(subprocess.list2cmdline(
                [os.path.join(root, 'yaca.exe')] + arguments))
            assert kernel.CreateProcessW(None, command, None, None, False, 0x14,
                None, os.path.join(root, 'workspace'), C.byref(startup), C.byref(self.process)), C.GetLastError()
            assert kernel.ResumeThread(self.process.thread) != 0xffffffff
            # XP completes console initialization during process startup.
            # Attaching to the still-suspended process can retain a blank buffer.
            time.sleep(.5)
            kernel.FreeConsole()
            try:
                assert kernel.AttachConsole(self.process.pid), C.GetLastError()
                self.input = kernel.CreateFileW('CONIN$', 0xc0000000, 3, None, 3, 0, None)
                self.output = kernel.CreateFileW('CONOUT$', 0xc0000000, 3, None, 3, 0, None)
                self.before = self.modes()
            except Exception:
                self.close()
                raise

        # Checks modes in windows console agent smoke.
        #@param self Console Owner of the proof fixture and its resources.
        #@return tuple[int,int] modes Current console input and output mode flags.
        def modes(self):
            a, b = W.DWORD(), W.DWORD()
            assert kernel.GetConsoleMode(self.input, C.byref(a))
            assert kernel.GetConsoleMode(self.output, C.byref(b))
            return a.value, b.value

        # Checks screen in windows console agent smoke.
        #@param self Console Owner of the proof fixture and its resources.
        #@return str text Current visible console screen contents.
        def screen(self):
            state, received = SCREEN(), W.DWORD()
            # The application may activate its own screen buffer after startup.
            # Retain the original handle for mode checks, read the active buffer.
            active = kernel.CreateFileW('CONOUT$', 0x80000000, 3, None, 3, 0, None)
            try:
                assert kernel.GetConsoleScreenBufferInfo(active, C.byref(state))
                rows = min(state.cursor.y + 2, state.size.y)
                lines = []
                for row in range(max(0, rows - 400), rows):
                    text = C.create_unicode_buffer(state.size.x + 1)
                    assert kernel.ReadConsoleOutputCharacterW(active, text,
                        state.size.x, COORD(0, row), C.byref(received))
                    # DBCS characters occupy two cells but one WCHAR.
                    assert 0 < received.value <= state.size.x, 'invalid console row read'
                    lines.append(text[:received.value].rstrip())
            finally:
                kernel.CloseHandle(active)
            data = '\n'.join(lines).rstrip()
            with open(os.path.join(evidence, self.name + '-screen-state.txt'), 'w') as stream:
                stream.write('size=%s,%s cursor=%s,%s requested=%s received=%s prefix=%r\n' % (
                    state.size.x, state.size.y, state.cursor.x, state.cursor.y,
                    rows * state.size.x, received.value, data[:256]))
            with open(os.path.join(evidence, self.name + '-screen.txt'), 'wb') as stream:
                stream.write(data.encode('utf-8'))
            return data

        # Waits for the expected terminal transcript marker.
        #@param self Console Owner of the proof fixture and its resources.
        #@param value object Candidate value under validation.
        #@param timeout float Maximum wait time in seconds.
        #@return str text Screen text after the expected marker appears.
        def expect(self, value, timeout=90):
            end = time.time() + timeout
            while time.time() < end:
                data = self.screen()
                if value in data: return data
                assert kernel.WaitForSingleObject(self.process.process, 0) == 258, 'child exited before ' + value
                time.sleep(.05)
            raise AssertionError('console timed out before ' + value)

        # Sends one terminal input line to the running Agent.
        #@param self Console Owner of the proof fixture and its resources.
        #@param text object The text supplied to this proof operation.
        #@return None No value; the operation updates proof state or raises on failure.
        def send(self, text):
            for character in text + '\r':
                event, written = INPUT(), W.DWORD()
                event.type = 1
                event.event.key.down = True
                event.event.key.repeat = 1
                event.event.key.key = 13 if character == '\r' else 0
                event.event.key.character.unicode = character
                assert kernel.WriteConsoleInputW(self.input, C.byref(event), 1, C.byref(written)) and written.value == 1

        # Checks finish in windows console agent smoke.
        #@param self Console Owner of the proof fixture and its resources.
        #@return None result No value; waits for and checks the console child exit.
        def finish(self):
            self.send('.quit')
            assert kernel.WaitForSingleObject(self.process.process, 10000) == 0
            result = W.DWORD()
            assert kernel.GetExitCodeProcess(self.process.process, C.byref(result)) and result.value == 0
            assert self.modes() == self.before, 'console modes were not restored'
            self.screen()

        # Checks close in windows console agent smoke.
        #@param self Console Owner of the proof fixture and its resources.
        #@return None result No value; releases console and child-process handles.
        def close(self):
            if self.process.process:
                if kernel.WaitForSingleObject(self.process.process, 0) == 258:
                    kernel.TerminateProcess(self.process.process, 124)
                    kernel.WaitForSingleObject(self.process.process, 5000)
                kernel.CloseHandle(self.process.process)
                kernel.CloseHandle(self.process.thread)
            for handle in (self.input, self.output):
                if handle and handle != C.c_void_p(-1).value: kernel.CloseHandle(handle)
            kernel.FreeConsole()

    child = None
    try:
        child = Console([], 'first-run')
        for prompt, answer in [('Model name', 'ConsoleTest'), ('Protocol (', ''),
                ('Enable this Model?', ''), ('Endpoint:', 'http://127.0.0.1:%d/chat' % server.server_port),
                ('Remote model:', 'mock'), ('Context length (tokens)', '32768'),
                ('Maximum output tokens', '4096'), ('Key (hidden;', '')]:
            child.expect(prompt); child.send(answer)
        child.expect('Type APPLY'); assert not requests
        child.send('APPLY'); child.expect('>>')
        assert os.path.isfile(os.path.join(root, '__yaca__', 'config.ini'))
        child.send('.side obsolete'); child.expect('UsageError: unknown command line')
        child.send('.status'); child.expect('state: draft-ready')
        child.send('.multiline'); child.expect('Multiline input:')
        child.send(u'\u4e2d\u6587 42'); child.send('Reply exactly 42.'); child.send('.ask')
        screen = child.expect('Ask ask-1 outcome: completed')
        assert '[TOOL ' not in screen and len(requests) == 1
        assert u'\u4e2d\u6587 42' in json.dumps(requests[0], ensure_ascii=False)
        match = re.search(r'Context saved:.*\[([A-F0-9]{16})\]', screen)
        assert match, 'saved Context hash was not displayed'
        selector = match.group(1)
        child.finish(); child.close(); child = None
        child = Console(['--continue', selector], 'reopened')
        child.expect('>>'); child.send('.ask Reply exactly 42.')
        child.expect('Ask ask-2 outcome: completed')
        assert len(requests) == 2
        child.finish()
        with open(os.path.join(evidence, 'result.txt'), 'w') as stream:
            stream.write('windows-console-agent=PASS setup=offline ask=no-tools Context=reopened modes=restored\n')
        print('windows-console-agent=PASS')
    finally:
        if child is not None: child.close()
        server.shutdown(); server.server_close(); thread.join(5)


if __name__ == '__main__':
    main()
