#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-10-11
# File: windows_console_agent_smoke.py
# Description: Native Windows console setup and authorized online Agent journeys with recorded approvals, persistence and console restoration.

"""Native Windows console setup and explicitly authorized online journeys.

Supply a new candidate directory containing only yaca.exe. Tests first setup,
pure Ask, persistence/reopen and console mode restoration. No real model is used.
Run with Python 2.7 or 3 on the target Windows machine.
With --online, use an already configured isolated directory and its real model.
"""
from __future__ import print_function
import argparse
import binascii
import ctypes as C
from ctypes import wintypes as W
import json
import os
import re
import subprocess
import threading
import time
from terminal_evidence import verify_lua_approval, verify_lua_execution, verify_recalled_token
try:
    from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
except ImportError:
    from http.server import HTTPServer, BaseHTTPRequestHandler
try:
    text_type = unicode
except NameError:
    text_type = str


#@class COORD Mutable Win32 coordinate value passed by value to console APIs; owns no handles.
#@field x SHORT Horizontal cell coordinate or buffer width.
#@field y SHORT Vertical cell coordinate or buffer height.
class COORD(C.Structure):
    _fields_ = [('x', W.SHORT), ('y', W.SHORT)]
#@class RECT Mutable inclusive console viewport returned inside SCREEN; owns no resources.
#@field left SHORT Leftmost visible column.
#@field top SHORT First visible row.
#@field right SHORT Rightmost visible column.
#@field bottom SHORT Last visible row.
class RECT(C.Structure):
    _fields_ = [(name, W.SHORT) for name in ('left', 'top', 'right', 'bottom')]
#@class SCREEN Caller-owned CONSOLE_SCREEN_BUFFER_INFO storage filled by the Windows API.
#@field size COORD Screen buffer dimensions in cells.
#@field cursor COORD Current output cursor position.
#@field attributes WORD Current text attributes.
#@field window RECT Current visible viewport.
#@field maximum COORD Maximum window dimensions supported by this console.
class SCREEN(C.Structure):
    _fields_ = [('size', COORD), ('cursor', COORD), ('attributes', W.WORD),
                ('window', RECT), ('maximum', COORD)]
#@class STARTUP Caller-owned STARTUPINFOW layout borrowed only during CreateProcessW.
#@field cb DWORD Complete structure size.
#@field reserved LPWSTR Unused reserved pointer, kept null.
#@field desktop LPWSTR Optional desktop selector, kept null.
#@field title LPWSTR Optional console title, kept null.
#@field x DWORD Unused initial window horizontal position.
#@field y DWORD Unused initial window vertical position.
#@field width DWORD Unused initial window width.
#@field height DWORD Unused initial window height.
#@field columns DWORD Requested 240-column buffer keeps bounded approval arguments on one line.
#@field rows DWORD Requested 4000-row buffer avoids overwriting this bounded test's output.
#@field fill DWORD Unused initial console attributes.
#@field flags DWORD STARTF_USESHOWWINDOW and STARTF_USECOUNTCHARS select a hidden bounded test console.
#@field show WORD SW_HIDE for the test's own console window.
#@field reserved_size WORD Unused reserved byte count.
#@field reserved_bytes void* Unused reserved data pointer.
#@field input HANDLE Unused startup stdin override.
#@field output HANDLE Unused startup stdout override.
#@field error HANDLE Unused startup stderr override.
class STARTUP(C.Structure):
    _fields_ = [('cb', W.DWORD), ('reserved', W.LPWSTR), ('desktop', W.LPWSTR),
        ('title', W.LPWSTR)] + [(name, W.DWORD) for name in
        ('x', 'y', 'width', 'height', 'columns', 'rows', 'fill', 'flags')] + [
        ('show', W.WORD), ('reserved_size', W.WORD), ('reserved_bytes', C.c_void_p),
        ('input', W.HANDLE), ('output', W.HANDLE), ('error', W.HANDLE)]
#@class PROCESS Mutable PROCESS_INFORMATION returned for the one child exclusively owned by Console.
#@field process HANDLE Child process reference closed by Console.close.
#@field thread HANDLE Initial suspended thread reference closed by Console.close.
#@field pid DWORD Child PID used for AttachConsole.
#@field tid DWORD Initial child thread identity.
class PROCESS(C.Structure):
    _fields_ = [('process', W.HANDLE), ('thread', W.HANDLE), ('pid', W.DWORD), ('tid', W.DWORD)]
#@class CHARACTER Win32 KEY_EVENT_RECORD character union; only its Unicode member is populated.
#@field unicode WCHAR One UTF-16 BMP input character.
#@field ascii char Alternate unused one-byte view.
class CHARACTER(C.Union):
    _fields_ = [('unicode', W.WCHAR), ('ascii', C.c_char)]
#@class KEY Mutable native key event copied into the independently owned test console input queue.
#@field down BOOL True for each injected key-down record.
#@field repeat WORD One logical repetition.
#@field key WORD VK_RETURN for Enter, zero for ordinary injected text.
#@field scan WORD Unused scan code, kept zero.
#@field character CHARACTER Unicode character delivered to the child.
#@field control DWORD Unused modifier flags, kept zero.
class KEY(C.Structure):
    _fields_ = [('down', W.BOOL), ('repeat', W.WORD), ('key', W.WORD),
        ('scan', W.WORD), ('character', CHARACTER), ('control', W.DWORD)]
#@class EVENT Native INPUT_RECORD payload union with key data and ABI-sized padding.
#@field key KEY Injected key event.
#@field padding byte[16] Maintains the Windows event-union size.
class EVENT(C.Union):
    _fields_ = [('key', KEY), ('padding', C.c_byte * 16)]
#@class INPUT Caller-owned INPUT_RECORD consumed synchronously by WriteConsoleInputW.
#@field type WORD KEY_EVENT discriminator, set to one.
#@field event EVENT One populated Unicode key payload.
class INPUT(C.Structure):
    _fields_ = [('type', W.WORD), ('event', EVENT)]


# Run offline setup or an explicitly authorized online Agent journey in independent native consoles.
#@param none No arguments.
#@return None No value after the selected setup or real-model journey and both child mode checks pass.
#@error Raises on invalid staging, incorrect request/output, child exit or mode mismatch.
#@effect Offline mode starts a loopback fixture and creates configuration; online mode uses the existing model. Both write bounded evidence and create hidden consoles.
#@ownership The finally block releases the current child handles and shuts down the owned server/thread.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    parser.add_argument('evidence')
    parser.add_argument('--online', action='store_true', help='use the existing authorized real model configuration')
    args = parser.parse_args()
    root = os.path.abspath(args.directory)
    if not isinstance(root, text_type): root = root.decode('mbcs')
    evidence = os.path.abspath(args.evidence)
    assert not os.path.exists(evidence), 'evidence directory must be new'
    os.mkdir(evidence)
    if args.online:
        assert os.path.isfile(os.path.join(root, '__yaca__', 'config.ini')), 'online candidate must be configured'
        assert os.path.isdir(os.path.join(root, 'workspace')), 'online workspace must exist'
    else:
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

    #@class Provider One local synthetic request handler; main owns its HTTP server and mutable request ledger.
    #@field headers HTTPMessage Inherited request headers inspected to reject credentials.
    #@field rfile stream Inherited bounded request-body input.
    #@field wfile stream Inherited response output closed by HTTPServer.
    class Provider(BaseHTTPRequestHandler):
        # Suppresses default proof-server request logging.
        #@param self Provider Active loopback request handler.
        #@param unused ... Ignored standard-library logging format and arguments.
        #@return None No value; suppresses inherited stderr request logging.
        def log_message(self, *unused): pass
        # Handles a proof HTTP POST and records its request evidence.
        #@param self Provider Active synthetic OpenAI-compatible request handler.
        #@return None No value after one fixed 42 response is written.
        #@error Raises for oversized/invalid bodies, credential headers or advertised tools.
        #@effect Saves the request ledger and emits bounded streaming or JSON fixture bytes over loopback.
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

    server, thread = None, None
    if not args.online:
        server = HTTPServer(('127.0.0.1', 0), Provider)
        thread = threading.Thread(target=server.serve_forever)
        thread.daemon = True
        thread.start()

    #@class Console Owns exactly one actual yaca child, its console input/output handles and captured mode baseline.
    #@field name str Safe probe label for the evidence filenames.
    #@field input HANDLE Owned CONIN$ reference released by close.
    #@field output HANDLE Owned original CONOUT$ reference used for mode checks.
    #@field process PROCESS Owned child process/thread references and identifiers.
    #@field before tuple[int,int] Console modes observed immediately after startup/attachment.
    class Console:
        # Start the actual child in a new hidden console, then attach only this probe to its handles.
        #@param self Console New owner with no previously acquired child.
        #@param arguments list[str] Additional yaca arguments; empty for first setup.
        #@param name str Evidence label identifying this child session.
        #@return None No value after process, console handles and observed mode baseline are acquired.
        #@error Raises on process creation, initial-thread resume, attachment or console API failure.
        #@effect Starts the child suspended in a new console, resumes it, then detaches the probe's prior console.
        #@ownership Owns returned process/thread and CONIN$/CONOUT$ handles; any post-creation failure closes acquired resources.
        def __init__(self, arguments, name):
            self.name, self.input, self.output = name, None, None
            self.process = PROCESS()
            startup = STARTUP(); startup.cb = C.sizeof(startup)
            startup.flags = 9; startup.show = 0
            startup.columns = 240; startup.rows = 4000
            command = C.create_unicode_buffer(subprocess.list2cmdline(
                [os.path.join(root, 'yaca.exe')] + arguments))
            assert kernel.CreateProcessW(None, command, None, None, False, 0x14,
                None, os.path.join(root, 'workspace'), C.byref(startup), C.byref(self.process)), C.GetLastError()
            try:
                assert kernel.ResumeThread(self.process.thread) != 0xffffffff
                # XP completes console initialization during process startup.
                # Attaching to the still-suspended process can retain a blank buffer.
                time.sleep(.5)
                kernel.FreeConsole()
                assert kernel.AttachConsole(self.process.pid), C.GetLastError()
                self.input = kernel.CreateFileW('CONIN$', 0xc0000000, 3, None, 3, 0, None)
                self.output = kernel.CreateFileW('CONOUT$', 0xc0000000, 3, None, 3, 0, None)
                self.before = self.modes()
            except Exception:
                self.close()
                raise

        # Read mode flags from this owner's retained input and original output handles.
        #@param self Console Attached child owner with valid retained handles.
        #@return tuple[int,int] modes Current console input and output mode flags.
        def modes(self):
            a, b = W.DWORD(), W.DWORD()
            assert kernel.GetConsoleMode(self.input, C.byref(a))
            assert kernel.GetConsoleMode(self.output, C.byref(b))
            return a.value, b.value

        # Read a bounded tail from the child's active screen buffer and save Unicode evidence.
        #@param self Console Owner attached to the current actual child console.
        #@return str text At most the last 400 populated screen rows, without trailing spaces.
        #@error Raises on screen API failure or invalid returned row counts.
        #@effect Replaces only this session's screen evidence; opens/closes one temporary active-buffer handle.
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
        #@param self Console Actual child owner whose screen is being observed.
        #@param value str Required literal output marker.
        #@param timeout float Maximum wait time in seconds.
        #@param occurrence int Required marker count in the retained screen tail; defaults to one and prevents old completion markers satisfying later phases.
        #@return str text Screen tail containing the required marker.
        #@error Raises if the child exits or the wall-clock deadline expires before the marker.
        #@effect Polls and records the owned screen without sending input.
        def expect(self, value, timeout=90, occurrence=1):
            end = time.time() + timeout
            while time.time() < end:
                data = self.screen()
                if data.count(value) >= occurrence: return data
                assert kernel.WaitForSingleObject(self.process.process, 0) == 258, 'child exited before ' + value
                time.sleep(.05)
            raise AssertionError('console timed out before ' + value)

        # Sends one terminal input line to the running Agent.
        #@param self Console Owner of the input queue receiving the test line.
        #@param text str|unicode BMP text submitted with one final Enter; no command is interpreted by this helper.
        #@return None No value after every key-down record is acknowledged.
        #@error Raises if a character cannot fit WCHAR or an input record is not accepted.
        #@effect Injects only this child's native console queue through WriteConsoleInputW.
        def send(self, text):
            for character in text + '\r':
                event, written = INPUT(), W.DWORD()
                event.type = 1
                event.event.key.down = True
                event.event.key.repeat = 1
                event.event.key.key = 13 if character == '\r' else 0
                event.event.key.character.unicode = character
                assert kernel.WriteConsoleInputW(self.input, C.byref(event), 1, C.byref(written)) and written.value == 1

        # Request normal application close, then verify exit and restoration to the observed baseline.
        #@param self Console Running child whose session is ready to quit.
        #@return None No value after exit zero and matching input/output modes.
        #@error Raises on a ten-second timeout, nonzero child status or mismatched mode flags.
        #@effect Sends .quit, waits for child completion and records the final screen.
        def finish(self):
            self.send('.quit')
            assert kernel.WaitForSingleObject(self.process.process, 10000) == 0
            result = W.DWORD()
            assert kernel.GetExitCodeProcess(self.process.process, C.byref(result)) and result.value == 0
            assert self.modes() == self.before, 'console modes were not restored'
            self.screen()

        # Release this probe's child and handles after success or failed assertions.
        #@param self Console Owner closed exactly once by the enclosing lifecycle.
        #@return None No value; releases retained process/thread/input/output handles and detaches the probe console.
        #@effect Terminates only a still-running owned child with status 124 and waits up to five seconds.
        #@ownership Consumes this owner's handle references; repeated close is not supported.
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

    # Preserve one complete observed phase before later screen updates replace the live snapshot.
    #@param name str Fixed evidence phase basename selected by this driver.
    #@param screen str|unicode Actual native console text already read from the owned child.
    #@return None No value; UTF-8 phase evidence is saved once.
    #@effect Writes only the selected phase file below the new evidence directory.
    def save_phase(name, screen):
        path = os.path.join(evidence, name + '.txt')
        assert not os.path.exists(path)
        with open(path, 'wb') as stream:
            stream.write(screen.encode('utf-8'))

    child = None
    try:
        if args.online:
            child = Console([], 'online')
            child.expect('>>')
            child.send('.status'); child.expect('state: draft-ready')
            child.send('.multiline'); child.expect('Multiline input:')
            child.send(u'\u4e2d\u6587 input check'); child.send('.show')
            child.expect(u'\u4e2d\u6587 input check'); child.send('.cancel')
            child.expect('Multiline draft discarded.')
            child.send('.ask Reply with exactly: 42. Use no tools.')
            screen = child.expect('Ask ask-1 outcome: completed', 180)
            assert re.search(r'\[ASK ask-1\]\s+42\s', screen)
            assert '[TOOL ' not in screen
            save_phase('first-ask', screen)
            child.send('Call the built-in lua tool exactly once with code print(6*7). '
                       'Report the actual result briefly, then finish. Use no other tool.')
            screen = child.expect('default: deny', 180)
            verify_lua_approval(screen.encode('utf-8'))
            save_phase('verified-approval', screen)
            child.send('allow approval-1 once')
            child.expect('Turn outcome: completed', 180)
            child.send('.ask What was the numeric result? Answer with the number only.')
            screen = child.expect('Ask ask-2 outcome: completed', 180)
            assert re.search(r'\[ASK ask-2\]\s+42\s', screen)
            verify_lua_execution(screen.encode('utf-8'))
            save_phase('verified-lua-execution', screen)
            token = 'yaca-memory-' + binascii.hexlify(os.urandom(8)).decode('ascii')
            child.send('Remember this verification token in this conversation: ' + token
                       + '. Reply with exactly STORED, then finish. Use no tools.')
            screen = child.expect('Turn outcome: completed', 180, occurrence=2)
            match = re.search(r'Context saved:.*\[([A-F0-9]{16})\]', screen)
            assert match, 'saved Context identity is unavailable'
            selector = match.group(1)
            save_phase('durable-token-turn', screen)
            child.finish(); child.close(); child = None
            child = Console(['--continue', selector], 'online-reopened')
            child.expect('>>')
            child.send('.ask What verification token did I ask you to remember? Reply with the exact token only.')
            screen = child.expect('Ask ask-3 outcome: completed', 180)
            verify_recalled_token(screen.encode('utf-8'), token)
            save_phase('verified-recall', screen)
            child.finish()
            with open(os.path.join(evidence, 'result.txt'), 'w') as stream:
                stream.write('windows-console-agent=PASS provider=real approval=verified lua=once Ask=no-tools Context=nonce-recalled modes=restored\n')
            print('windows-console-agent=PASS provider=real')
            return
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
        if server is not None:
            server.shutdown(); server.server_close(); thread.join(5)


if __name__ == '__main__':
    main()
