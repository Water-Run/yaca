#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-10-23
# File: windows_console_agent_smoke.py
# Description: Native Windows console setup, default editing and both-provider tool-feedback journeys, plus authorized online approval and persistence checks.

"""Native Windows console setup and explicitly authorized online journeys.

Supply a new candidate directory containing only yaca.exe. Tests first setup,
Tab/history editing, pure Ask, tool-error correction, normal completion, persisted
reopen and console mode restoration against either loopback protocol.
Run with Python 2.7 or 3 on the target Windows machine.
With --online, use an already configured isolated directory and its real model.
"""
from __future__ import print_function
import argparse
import binascii
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
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


# Launch the candidate from an already initialized hidden console and record actual pre/post modes.
#@param receipt str Path for this host's final JSON receipt; a separate .started file identifies the child.
#@param command list[str] Exact candidate executable and arguments, passed without a shell.
#@return int Candidate process exit code after its actual modes are recorded.
#@effect Starts and joins one child in the inherited private test console, reads modes and writes bounded JSON evidence.
#@error Raises on invalid console handles or process/file failures; terminates its own live child on Python exceptions.
def console_host(receipt, command):
    kernel = C.windll.kernel32
    kernel.GetStdHandle.restype = W.HANDLE
    kernel.GetConsoleMode.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
    input_handle, output_handle = kernel.GetStdHandle(-10), kernel.GetStdHandle(-11)
    before_input, before_output = W.DWORD(), W.DWORD()
    assert kernel.GetConsoleMode(input_handle, C.byref(before_input))
    assert kernel.GetConsoleMode(output_handle, C.byref(before_output))
    child = subprocess.Popen(command)
    try:
        with open(receipt + '.starting', 'w') as stream:
            json.dump(dict(pid=child.pid, before=[before_input.value, before_output.value]), stream)
        os.rename(receipt + '.starting', receipt + '.started')
        result = child.wait()
        after_input, after_output = W.DWORD(), W.DWORD()
        assert kernel.GetConsoleMode(input_handle, C.byref(after_input))
        assert kernel.GetConsoleMode(output_handle, C.byref(after_output))
        with open(receipt, 'w') as stream:
            json.dump(dict(exit_code=result, before=[before_input.value, before_output.value],
                after=[after_input.value, after_output.value]), stream)
        return result
    finally:
        if child.poll() is None:
            child.terminate()
            child.wait()


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
    parser.add_argument('--protocol', choices=('openai-chat', 'anthropic-messages'), default='openai-chat',
        help='protocol exercised by the offline loopback fixture')
    parser.add_argument('--busy-input', action='store_true', help='verify an unsubmitted draft during a delayed offline Ask')
    parser.add_argument('--upgrade-core', help='replace the closed first-session core before reopening the same Context')
    args = parser.parse_args()
    assert not args.upgrade_core or args.online, 'upgrade verification requires an online persisted Context'
    assert not args.busy_input or not args.online, 'busy input probe requires the loopback fixture'
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
    kernel.SetConsoleScreenBufferSize.argtypes = [W.HANDLE, COORD]
    kernel.ReadConsoleOutputCharacterW.argtypes = [W.HANDLE, W.LPWSTR, W.DWORD, COORD, C.POINTER(W.DWORD)]
    kernel.WriteConsoleInputW.argtypes = [W.HANDLE, C.POINTER(INPUT), W.DWORD, C.POINTER(W.DWORD)]
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    kernel.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
    kernel.ResumeThread.argtypes = [W.HANDLE]
    kernel.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    kernel.OpenProcess.restype = W.HANDLE
    requests = []
    request_arrived, release_response = threading.Event(), threading.Event()

    #@class Provider One local synthetic request handler; main owns its HTTP server and mutable request ledger.
    #@field headers HTTPMessage Inherited request headers inspected to reject credentials.
    #@field rfile stream Inherited bounded request-body input.
    #@field wfile stream Inherited response output closed by HTTPServer.
    class Provider(BaseHTTPRequestHandler):
        # Suppresses default proof-server request logging.
        #@param self Provider Active loopback request handler.
        #@param ... object Ignored standard-library format string followed by its formatting values.
        #@return None No value; suppresses inherited stderr request logging.
        def log_message(self, *unused): pass
        # Handles a proof HTTP POST and records its request evidence.
        #@param self Provider Active synthetic OpenAI-compatible request handler.
        #@return None No value after a scripted Ask, tool, correction, final answer or review response.
        #@error Raises for oversized/invalid bodies, credential headers or missing tool-result evidence.
        #@effect Saves synthetic requests and emits bounded streaming or JSON fixture bytes over loopback.
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            assert 0 < length <= 4 * 1024 * 1024
            request = json.loads(self.rfile.read(length).decode('utf-8'))
            assert not self.headers.get('Authorization'), 'no test credentials are permitted'
            requests.append(request)
            if args.busy_input and len(requests) in (1, 6):
                request_arrived.set()
                assert release_response.wait(20), 'busy input probe did not release its response'
            with open(os.path.join(evidence, 'request-%d.json' % len(requests)), 'wb') as stream:
                stream.write(json.dumps(request, ensure_ascii=False).encode('utf-8'))
            message = dict(role='assistant', content='42')
            finish = 'stop'
            contents = []
            for item in request['messages']:
                content = item.get('content', '')
                if isinstance(content, list):
                    contents.extend(block.get('text', '') for block in content if block.get('type') == 'text')
                else:
                    contents.append(content)
            system = request.get('system', [])
            if isinstance(system, list):
                contents.extend(block.get('text', '') for block in system)
            elif system:
                contents.append(system)
            if request.get('tools'):
                results = []
                for content in contents:
                    if not content.startswith('YACA-MODEL-VIEW/1\n'):
                        continue
                    facts = ET.fromstring(content.split('\n\n', 1)[1])
                    for event in facts.findall('Event'):
                        if event.get('type') == 'tool_result':
                            results.append({field.get('name'): field.text or '' for field in event.findall('Field')})
                if len(results) < 2:
                    path = 'missing.txt' if not results else 'fixture.txt'
                    if results:
                        assert results[-1]['errorId'] == 'NotFound', 'missing file failure was not returned to model'
                    message = dict(role='assistant', content='Reading ' + path,
                        tool_calls=[dict(id='read-' + str(len(results)), type='function',
                            function=dict(name='read', arguments=json.dumps(dict(
                                path=path, start_line=1, max_lines=10))))])
                    finish = 'tool_calls'
                else:
                    assert len(results) == 2 and 'LOOP_OK_42' in results[-1]['body']
                    message['content'] = 'Verified fixture.txt contains LOOP_OK_42.'
            elif any('Review whether the bound completion claim' in content for content in contents):
                message['content'] = json.dumps(dict(verdict='pass', gap='', reason='Tool evidence matches.'))
            if args.protocol == 'anthropic-messages':
                blocks = [dict(type='text', text=message['content'])]
                for call in message.get('tool_calls', []):
                    blocks.append(dict(type='tool_use', id=call['id'], name=call['function']['name'],
                        input=json.loads(call['function']['arguments'])))
                stop = 'tool_use' if finish == 'tool_calls' else 'end_turn'
                if request.get('stream'):
                    events = [('message_start', dict(type='message_start', message=dict(
                        id='console-response', type='message', role='assistant', model='mock',
                        content=[], usage=dict(input_tokens=100, output_tokens=0))))]
                    for index, block in enumerate(blocks):
                        events.append(('content_block_start', dict(type='content_block_start',
                            index=index, content_block=block)))
                        events.append(('content_block_stop', dict(type='content_block_stop', index=index)))
                    events.extend([('message_delta', dict(type='message_delta', delta=dict(stop_reason=stop),
                        usage=dict(output_tokens=30))), ('message_stop', dict(type='message_stop'))])
                    body = ''.join('event: ' + name + '\ndata: ' + json.dumps(event) + '\n\n'
                        for name, event in events)
                    content_type = 'text/event-stream'
                else:
                    body = json.dumps(dict(id='console-response', type='message', role='assistant',
                        model='mock', content=blocks, stop_reason=stop,
                        usage=dict(input_tokens=100, output_tokens=30)))
                    content_type = 'application/json'
            elif request.get('stream'):
                delta = dict(message)
                if delta.get('tool_calls'):
                    delta['tool_calls'][0]['index'] = 0
                chunks = [dict(id='console-ask', choices=[dict(index=0,
                    delta=delta, finish_reason=None)]),
                    dict(id='console-ask', choices=[dict(index=0, delta={}, finish_reason=finish)])]
                body = ''.join('data: ' + json.dumps(item) + '\n\n' for item in chunks) + 'data: [DONE]\n\n'
                content_type = 'text/event-stream'
            else:
                body = json.dumps(dict(id='console-ask', choices=[dict(index=0,
                    message=message, finish_reason=finish)]))
                content_type = 'application/json'
            body = body.encode('utf-8')
            try:
                self.send_response(200)
                self.send_header('Content-Type', content_type)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except (IOError, OSError):
                if not args.busy_input or len(requests) != 6:
                    raise

    server, thread = None, None
    if not args.online:
        server = HTTPServer(('127.0.0.1', 0), Provider)
        thread = threading.Thread(target=server.serve_forever)
        thread.daemon = True
        thread.start()

    #@class Console Owns one hidden host and its yaca child, console handles and an independently captured mode baseline.
    #@field name str Safe probe label for the evidence filenames.
    #@field input HANDLE Owned CONIN$ reference released by close.
    #@field output HANDLE Owned original CONOUT$ reference used for mode checks.
    #@field process PROCESS Owned host process/thread references and identifiers.
    #@field before tuple[int,int] Console modes captured by the host before starting yaca.
    #@field receipt str Host-owned JSON path recording modes before the candidate starts and after it exits.
    #@field app_handle HANDLE Optional terminate/synchronize reference to the candidate outer process, owned by this probe.
    class Console:
        # Start the actual child in a new hidden console, then attach only this probe to its handles.
        #@param self Console New owner with no previously acquired child.
        #@param arguments list[str] Additional yaca arguments; empty for first setup.
        #@param name str Evidence label identifying this child session.
        #@return None No value after process, console handles and observed mode baseline are acquired.
        #@error Raises on process creation, initial-thread resume, attachment or console API failure.
        #@effect Starts a hidden console child, resumes/attaches it, and fixes only its own screen buffer width before submitting input.
        #@ownership Owns returned process/thread and CONIN$/CONOUT$ handles; any post-creation failure closes acquired resources.
        def __init__(self, arguments, name):
            self.name, self.input, self.output = name, None, None
            self.app_handle = None
            self.receipt = os.path.join(evidence, name + '-modes.json')
            self.process = PROCESS()
            startup = STARTUP(); startup.cb = C.sizeof(startup)
            startup.flags = 9; startup.show = 0
            startup.columns = 240; startup.rows = 4000
            command = C.create_unicode_buffer(subprocess.list2cmdline(
                [sys.executable, os.path.abspath(__file__), '--console-host', self.receipt,
                    os.path.join(root, 'yaca.exe')] + arguments))
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
                assert kernel.SetConsoleScreenBufferSize(self.output, COORD(240, 4000)), C.GetLastError()
                dimensions = SCREEN()
                assert kernel.GetConsoleScreenBufferInfo(self.output, C.byref(dimensions))
                assert dimensions.size.x >= 240, 'console cannot retain an unwrapped approval card'
                deadline = time.time() + 5
                while not os.path.isfile(self.receipt + '.started'):
                    assert time.time() < deadline, 'console host did not start the candidate'
                    time.sleep(.05)
                with open(self.receipt + '.started') as stream:
                    started = json.load(stream)
                self.before = tuple(started['before'])
                self.app_handle = kernel.OpenProcess(0x00100001, False, started['pid'])
                assert self.app_handle, 'candidate process is unavailable'
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

        # Type exact editable text into the owned console without submitting it.
        #@param self Console Owner of the input queue receiving the test text.
        #@param text str|unicode BMP text or editing control characters.
        #@return None After every input record is accepted.
        #@error Raises on an invalid WCHAR or rejected console event.
        #@effect Injects only this child's native input queue; does not append Enter.
        def type_text(self, text):
            for character in text:
                event, written = INPUT(), W.DWORD()
                event.type = 1
                event.event.key.down = True
                event.event.key.repeat = 1
                event.event.key.key = 13 if character == '\r' else 0
                event.event.key.character.unicode = character
                assert kernel.WriteConsoleInputW(self.input, C.byref(event), 1, C.byref(written)) and written.value == 1

        # Sends one terminal input line to the running Agent.
        #@param self Console Owner of the input queue receiving the test line.
        #@param text str|unicode BMP text submitted with one final Enter; no command is interpreted by this helper.
        #@return None No value after every key-down record is acknowledged.
        #@error Raises if a character cannot fit WCHAR or an input record is not accepted.
        #@effect Injects only this child's native console queue through WriteConsoleInputW.
        def send(self, text):
            self.type_text(text + '\r')

        # Require the actual active input row and cursor to match the retained draft.
        #@param self Console Owner attached to the active child screen.
        #@param label str Evidence basename for this verified screen phase.
        #@param line str|unicode Expected row text after removing console padding.
        #@param column int Expected zero-based cursor column.
        #@return None After the row/cursor are observed within five seconds.
        #@effect Reads only this console and writes the observed screen to the evidence directory.
        #@error Raises on native read failure or mismatched final row/cursor.
        def assert_input(self, label, line, column):
            deadline = time.time() + 5
            while True:
                state, count = SCREEN(), W.DWORD()
                assert kernel.GetConsoleScreenBufferInfo(self.output, C.byref(state))
                row = C.create_unicode_buffer(state.size.x + 1)
                assert kernel.ReadConsoleOutputCharacterW(self.output, row, state.size.x,
                    COORD(0, state.cursor.y), C.byref(count))
                actual = row[:count.value].rstrip()
                if actual == line and state.cursor.x == column:
                    break
                if time.time() >= deadline:
                    self.screen()
                    raise AssertionError('input row/cursor mismatch: %r at %s, wanted %r at %s' % (
                        actual, state.cursor.x, line, column))
                time.sleep(.05)
            save_phase(label, self.screen())

        # Send one non-text editing key to the owned console without submitting a line.
        #@param self Console Owner of the test child's input queue.
        #@param key int Win32 virtual key code, such as VK_UP for native command history.
        #@param control int Optional native modifier mask; zero by default.
        #@return None No value after Windows accepts exactly one key record.
        #@effect Writes one key-down event to this child's console only.
        #@error Raises if the console rejects the key record.
        def send_key(self, key, control=0):
            event, written = INPUT(), W.DWORD()
            event.type = 1
            event.event.key.down = True
            event.event.key.repeat = 1
            event.event.key.key = key
            event.event.key.control = control
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
            with open(self.receipt) as stream:
                receipt = json.load(stream)
            assert receipt['exit_code'] == 0 and tuple(receipt['after']) == self.before, 'console modes were not restored'
            assert self.modes() == self.before, 'console mode changed after the candidate exited'
            self.screen()

        # Release this probe's child and handles after success or failed assertions.
        #@param self Console Owner closed exactly once by the enclosing lifecycle.
        #@return None No value; releases retained process/thread/input/output handles and detaches the probe console.
        #@effect Terminates only a still-running owned child with status 124 and waits up to five seconds.
        #@ownership Consumes this owner's handle references; repeated close is not supported.
        def close(self):
            if self.app_handle:
                if kernel.WaitForSingleObject(self.app_handle, 0) == 258:
                    kernel.TerminateProcess(self.app_handle, 124)
                    kernel.WaitForSingleObject(self.app_handle, 5000)
                kernel.CloseHandle(self.app_handle)
                self.app_handle = None
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

    # Wait for the admitted print-only turn while refusing every additional genuine approval card.
    #@param console Console Actual child that has received exactly one verified allow command.
    #@return str|unicode Screen text containing the completed turn after at most three additional denials.
    #@error Raises on child exit, a 180-second timeout or excessive repeated proposals.
    #@effect Sends only explicit deny commands for new complete Runtime cards; never grants another tool execution.
    def await_single_execution(console):
        deadline = time.time() + 180
        seen = {'approval-1'}
        denials = []
        while time.time() < deadline:
            screen = console.screen()
            if re.search(r'(?:^|\n)\[STATUS\]\nTurn outcome: completed(?:\n|$)', screen):
                with open(os.path.join(evidence, 'additional-denials.json'), 'w') as stream:
                    json.dump(denials, stream)
                return screen
            cards = list(re.finditer(r'(?:^|\n)\[ACTION (approval-[0-9]+)\]\n', screen))
            for card in cards:
                identity = card.group(1)
                if identity in seen:
                    continue
                tail = screen[card.end():]
                footer = 'allow ' + identity + ' once | deny ' + identity + ' | details ' + identity
                if footer not in tail or 'default: deny' not in tail:
                    continue
                assert len(denials) < 3, 'provider repeatedly requested extra approvals'
                console.send('deny ' + identity)
                seen.add(identity)
                denials.append(identity)
            assert kernel.WaitForSingleObject(console.process.process, 0) == 258, 'child exited during tool turn'
            time.sleep(.05)
        raise AssertionError('console timed out waiting for the single admitted tool turn')

    # Fingerprint the complete owned configuration/Context and workspace trees without exposing their contents.
    #@param none Uses only this isolated application's __yaca__ and workspace directories.
    #@return list[tuple] Sorted directory identities and regular-file sizes/digests.
    #@error Rejects symlink entries so no external tree can silently enter the preservation proof.
    #@effect Reads existing data files in bounded chunks; never writes their bytes or contents to logs.
    def data_inventory():
        records = []
        for leaf in ('__yaca__', 'workspace'):
            base = os.path.join(root, leaf)
            assert os.path.isdir(base) and not os.path.islink(base)
            for directory, directories, filenames in os.walk(base):
                records.append(('directory', os.path.relpath(directory, root)))
                for name in directories + filenames:
                    assert not os.path.islink(os.path.join(directory, name)), 'upgrade data contains a link'
                for name in filenames:
                    path = os.path.join(directory, name)
                    digest = hashlib.sha256()
                    size = 0
                    with open(path, 'rb') as stream:
                        while True:
                            block = stream.read(1048576)
                            if not block: break
                            size += len(block)
                            digest.update(block)
                    records.append(('file', os.path.relpath(path, root), size, digest.hexdigest()))
        return sorted(records)

    # Replace only the stopped executable and prove the entire owned data set is unchanged before reopening.
    #@param none Uses the explicit --upgrade-core path and the closed first-session executable.
    #@return None No value after different old/new core bytes and unchanged data are confirmed.
    #@error Raises on unchanged core input, failed copying, digest mismatch or any data alteration.
    #@effect Replaces yaca.exe in this isolated test directory and writes only public core digests and a preservation count.
    def replace_closed_core():
        destination = os.path.join(root, 'yaca.exe')
        replacement = os.path.abspath(args.upgrade_core)
        assert os.path.isfile(replacement) and not os.path.islink(replacement)
        with open(destination, 'rb') as stream:
            before_core = hashlib.sha256(stream.read()).hexdigest()
        with open(replacement, 'rb') as stream:
            after_core = hashlib.sha256(stream.read()).hexdigest()
        assert before_core != after_core, 'upgrade must change the core bytes'
        before_data = data_inventory()
        shutil.copyfile(replacement, destination)
        with open(destination, 'rb') as stream:
            assert hashlib.sha256(stream.read()).hexdigest() == after_core
        assert data_inventory() == before_data, 'core replacement altered preserved data'
        with open(os.path.join(evidence, 'upgrade.json'), 'w') as stream:
            json.dump({'old_core_sha256': before_core, 'new_core_sha256': after_core,
                       'data_entries': len(before_data), 'all_data_bytes_preserved': True}, stream, indent=2)

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
            await_single_execution(child)
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
            if args.upgrade_core:
                replace_closed_core()
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
        for prompt, answer in [('Model name', 'ConsoleTest'), ('Protocol (', args.protocol),
                ('Enable this Model?', ''), ('Endpoint:', 'http://127.0.0.1:%d/chat' % server.server_port),
                ('Remote model:', 'mock'), ('Context length (tokens)', '32768'),
                ('Maximum output tokens', '4096'), ('Key (hidden;', '')]:
            child.expect(prompt); child.send(answer)
        child.expect('Type APPLY'); assert not requests
        child.send('APPLY'); child.expect('>>')
        assert os.path.isfile(os.path.join(root, '__yaca__', 'config.ini'))
        child.send('.side obsolete'); child.expect('UsageError: unknown command line')
        child.send('.staX\b\t'); screen = child.expect('state: draft-ready')
        assert '\n>> .status\n' in screen, 'chat prompt and submitted command are not on the same line'
        child.send_key(38); child.send('')
        screen = child.expect('state: draft-ready', occurrence=2)
        assert screen.count('\n>> .status\n') == 2, 'Up did not recall the completed command'
        if args.busy_input:
            child.type_text(u'.ask \u4e2d\u6587 42')
            child.send_key(13, 0x0010)
            child.send('Reply exactly 42.')
        else:
            child.send('.multiline'); child.expect('Multiline input:')
            child.send(u'\u4e2d\u6587 42'); child.send('Reply exactly 42.'); child.send('.ask')
        if args.busy_input:
            assert request_arrived.wait(10), 'Ask was not dispatched'
            child.type_text(u'a\u4e2db')
            child.send_key(37)
            child.type_text('X')
            child.assert_input('unicode-middle', u'>> a\u4e2dXb', 7)
            child.type_text('\x03')
            child.assert_input('draft-cleared', '>>', 3)
            child.type_text('.sta')
            child.send_key(37)
            child.assert_input('busy-before', '>> .sta', 6)
            release_response.set()
        screen = child.expect('Ask ask-1 outcome: completed')
        if args.busy_input:
            child.assert_input('busy-after', '>> .sta', 6)
            child.send_key(35)
            child.type_text('\t')
            child.send('')
            child.expect('state: Idle')
        assert '[TOOL ' not in screen and len(requests) == 1
        assert u'\u4e2d\u6587 42' in json.dumps(requests[0], ensure_ascii=False)
        match = re.search(r'Context saved:.*\[([A-F0-9]{16})\]', screen)
        assert match, 'saved Context hash was not displayed'
        selector = match.group(1)
        with open(os.path.join(root, 'workspace', 'fixture.txt'), 'wb') as stream:
            stream.write(b'LOOP_OK_42\n')
        child.send('Read fixture.txt and report its contents.')
        screen = child.expect('Turn outcome: completed')
        assert 'Verified fixture.txt contains LOOP_OK_42.' in screen
        assert screen.count('result: error (NotFound)') == 1 and screen.count('result: ok') == 1
        assert '[TOOL tool-1]\nresult: error (NotFound)' in screen
        assert '[TOOL tool-2]\nresult: ok' in screen
        assert 'Model yielded without finish' not in screen
        assert len(requests) == 5, 'main must run missing read, corrected read, final answer and review'
        save_phase('verified-agent-loop', screen)
        if args.busy_input:
            request_arrived.clear(); release_response.clear()
            child.send('.ask cancel this delayed response')
            assert request_arrived.wait(10), 'cancellable Ask was not dispatched'
            child.type_text('\x03')
            cancelled_screen = child.expect('cancelled')
            assert 'AskModelResponseError' not in cancelled_screen, 'normal cancellation was displayed as an error'
            release_response.set()
            child.assert_input('request-cancelled', '>>', 3)
        child.finish(); child.close(); child = None
        child = Console(['--continue', selector], 'reopened')
        child.expect('>>'); child.send('.ask Reply exactly 42.')
        child.expect('Ask ask-%d outcome: completed' % (3 if args.busy_input else 2))
        assert len(requests) == (7 if args.busy_input else 6)
        child.finish()
        with open(os.path.join(evidence, 'result.txt'), 'w') as stream:
            stream.write('windows-console-agent=PASS protocol=' + args.protocol + ' setup=offline prompt=inline tool-error=corrected tool-result=returned normal-stop=completed review=passed Context=reopened modes=restored\n')
        print('windows-console-agent=PASS')
    finally:
        release_response.set()
        if child is not None: child.close()
        if server is not None:
            server.shutdown(); server.server_close(); thread.join(5)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--console-host':
        raise SystemExit(console_host(sys.argv[2], sys.argv[3:]))
    main()
