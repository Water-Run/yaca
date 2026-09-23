#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-09-23
# File: windows_portable_acceptance.py
# Description: Credential-free acceptance of a staged Windows portable test medium.

"""Credential-free acceptance of a staged Windows portable test medium.

The medium contains yaca.exe, onedir/, source/, tools/ and probes/. Each
subprocess gets a bounded deadline and a separate transcript. Python 2.7 and
3.x can drive this probe; optional development tools are checked when present.
"""
from __future__ import print_function
import ctypes
import os
import platform
import subprocess
import sys
import tempfile
import threading


# Runs the windows portable acceptance command and reports its status.
#@param none No arguments.
#@return bool failed Whether any portable acceptance case failed.
def main():
    root = os.path.dirname(os.path.abspath(__file__))
    evidence = os.path.join(root, 'evidence')
    if not os.path.isdir(evidence): os.mkdir(evidence)
    ctypes.windll.kernel32.SetErrorMode(3)
    summary = open(os.path.join(evidence, 'summary.txt'), 'w')
    failures = []

    # Prints one bounded acceptance-test observation.
    #@param message str Assertion or diagnostic message.
    #@return None No value; the operation updates proof state or raises on failure.
    def report(message):
        print(message)
        summary.write(message + '\n')
        summary.flush()

    # Runs the selected command and checks its expected output.
    #@param name str Selected fixture, component, or tool name.
    #@param command list[str] Command vector launched for qualification.
    #@param cwd Path Working directory for the qualification command.
    #@param timeout float Maximum wait time in seconds.
    #@param marker str Unique event marker used by recovery assertions.
    #@param env dict[str,str] Environment supplied to the child process.
    #@return bool accepted Whether the child emitted its expected acceptance marker.
    def run(name, command, cwd=None, timeout=120, marker=None, env=None):
        transcript = os.path.join(evidence, name + '.log')
        with open(transcript, 'wb') as stream:
            child = subprocess.Popen(command, cwd=cwd or root, stdin=open(os.devnull, 'rb'),
                stdout=stream, stderr=subprocess.STDOUT, env=env)
            timer = threading.Timer(timeout, child.kill)
            timer.start()
            try:
                code = child.wait()
            finally:
                timer.cancel()
        with open(transcript, 'rb') as stream: output = stream.read()
        ok = code == 0 and (marker is None or marker in output)
        report('%s=%s exit=%s' % (name, 'PASS' if ok else 'FAIL', code))
        if not ok: failures.append(name)
        return ok

    report('platform=' + platform.platform())
    report('medium=' + root)
    filesystem = ctypes.create_unicode_buffer(32)
    drive_root = os.path.splitdrive(root)[0] + '\\'
    if not isinstance(drive_root, type(u'')): drive_root = drive_root.decode('mbcs')
    assert ctypes.windll.kernel32.GetVolumeInformationW(drive_root, None, 0,
        None, None, None, filesystem, len(filesystem))
    report('medium_filesystem=' + filesystem.value)
    source = os.path.join(root, 'source')
    interpreter = os.path.join(root, 'onedir', 'inner.exe')
    native = os.path.join(root, 'onedir', '.luai', 'native', 'yaca_native.dll')
    lua = [interpreter, '--lua', '-E']
    bootstrap = os.path.join(root, 'native-bootstrap.lua')
    with open(bootstrap, 'w') as stream:
        stream.write("local module, script = table.remove(arg, 1), table.remove(arg, 1)\n"
            "package.cpath = module .. '/?.dll'\n"
            "arg[0] = script; dofile(script)\n")
    native_lua = lua + [bootstrap, os.path.dirname(native)]
    probe_source = os.path.join(source, '.tools', 'qualification')
    run('version', [os.path.join(root, 'yaca.exe'), '--version'], marker=b'yaca 0.1.0')
    run('lua-version', [os.path.join(root, 'yaca.exe'), '--lua', '-E', '-e',
        "assert(_VERSION == 'Lua 5.5'); print(6*7)"], marker=b'42')
    run('core-suite', lua + [os.path.join(source, 'test', 'run.lua')],
        cwd=source, timeout=300, marker=b' failed=0')
    for name, parent in [('fat-publication', root), ('ntfs-publication', tempfile.gettempdir())]:
        scratch = tempfile.mkdtemp(prefix='yaca publication ', dir=parent)
        run(name, native_lua + [os.path.join(probe_source, 'windows_native_smoke.lua'), scratch])
    for name in ('lua_tool', 'process_stdin'):
        scratch = tempfile.mkdtemp(prefix='yaca native ', dir=root)
        os.mkdir(os.path.join(scratch, 'reserved'))
        run(name, lua + [os.path.join(probe_source, name + '_smoke.lua'),
            source, native, interpreter, scratch], marker=b'=PASS')
    scratch = tempfile.mkdtemp(prefix='yaca unicode ', dir=root)
    run('unicode-long-path', [os.path.join(root, 'probes', 'unicode.exe'),
        os.path.join(root, 'yaca.exe'), scratch], marker=b'=PASS')
    run('console-reader', [os.path.join(root, 'probes', 'reader.exe')], marker=b'=PASS')
    run('console-unicode', [os.path.join(root, 'probes', 'console.exe'), native,
        os.path.join(evidence, 'console-screen.txt'), 'native'])
    run('std-tools', [sys.executable, '-E', '-S', '-B',
        os.path.join(probe_source, 'windows_std_smoke.py'), root,
        '--ssh-host', '192.168.5.10', '--ssh-host-key',
        'SHA256:OEXMjE2K6ecKXDYmOVQQH7myRu7clUjPVVjF5awTx2o',
        '--https-url', 'https://example.com/'], timeout=180, marker=b'7zip-roundtrip=PASS')
    python3 = os.path.join(root, 'tools', 'python3', 'python.exe')
    if os.path.isfile(python3):
        probe = os.path.join(root, 'python3-probe.py')
        run('python3', [python3, '-E', '-S', '-B', probe,
            os.path.dirname(python3)], marker=b'python34-portable=PASS')
    git = os.path.join(root, 'tools', 'git', 'cmd', 'git.exe')
    if os.path.isfile(git):
        scratch = tempfile.mkdtemp(prefix='yaca git ', dir=root)
        run('git-version', [git, '--version'], marker=b'2.10.0')
        run('git-init', [git, 'init', scratch], marker=b'Initialized')
        with open(os.path.join(scratch, 'hello.txt'), 'w') as stream: stream.write('portable\n')
        run('git-add', [git, 'add', 'hello.txt'], cwd=scratch)
        run('git-commit', [git, '-c', 'user.name=Yaca Test', '-c', 'user.email=test@example.invalid',
            'commit', '-m', 'portable test'], cwd=scratch)
    sqlite = os.path.join(root, 'tools', 'sqlite', 'sqlite3.exe')
    if os.path.isfile(sqlite):
        run('sqlite', [sqlite, ':memory:', 'select 6*7;'], marker=b'42')
    jq = os.path.join(root, 'tools', 'jq', 'jq.exe')
    if os.path.isfile(jq): run('jq', [jq, '-n', '6*7'], marker=b'42')
    compiler = os.path.join(root, 'tools', 'compiler', 'bin')
    if os.path.isfile(os.path.join(compiler, 'gcc.exe')):
        scratch = tempfile.mkdtemp(prefix='yaca compile ', dir=root)
        environment = os.environ.copy()
        environment['PATH'] = compiler + os.pathsep + environment.get('PATH', '')
        for language, binary, text in [('c', 'gcc.exe', '#include <stdio.h>\nint main(void){puts("compiler=42");return 0;}\n'),
            ('cpp', 'g++.exe', '#include <iostream>\nint main(){std::cout << "compiler=42\\n";}\n')]:
            with open(os.path.join(scratch, 'hello.' + language), 'w') as stream: stream.write(text)
            if run('compile-' + language, [os.path.join(compiler, binary),
                    'hello.' + language, '-o', 'hello-' + language + '.exe'], cwd=scratch, env=environment):
                run('run-' + language, [os.path.join(scratch, 'hello-' + language + '.exe')],
                    cwd=scratch, env=environment, marker=b'compiler=42')
        run('busybox', [os.path.join(compiler, 'busybox.exe'), 'printf', 'busybox=42'], marker=b'busybox=42')
    report('acceptance=%s failures=%s' % ('PASS' if not failures else 'FAIL', ','.join(failures)))
    summary.close()
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
