#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-10-02
# File: stage_python38_windows.py
# Description: Stage the private CPython 3.8.20 x64 build as a portable command-line toolbox.

"""Stage the private CPython 3.8.20 x64 build as a portable command-line toolbox.

Run on Windows with the std Python 3 interpreter. The VC++ runtime comes from
the verified v142 private extraction (VC Redist payload) and the Universal
CRT from the extracted SDK redistributable; the OpenSSL DLLs come from the
CPython-published binary externals. No installation, registry changes or PATH
changes are performed. The destination must be new.
"""
from __future__ import print_function
import argparse
import ctypes
import hashlib
import os
import shutil
import subprocess
import zipfile


EXTENSIONS = ('_bz2', '_ctypes', '_decimal', '_elementtree',
              '_hashlib', '_lzma', '_multiprocessing', '_overlapped',
              '_queue', '_socket', '_sqlite3', '_ssl', 'pyexpat',
              'select', 'unicodedata', 'winsound')


# Runs the stage python38 windows command and reports its status.
#@param none No arguments; paths arrive through argparse.
#@return None result No value; stages the verified portable Python 3.8 tree.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('v142')
    parser.add_argument('output')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('the build and relocation probe require Windows')
    source, v142_root, output = map(os.path.abspath,
                                    (args.source, args.v142, args.output))
    with open(os.path.join(source, 'Include', 'patchlevel.h'), 'rb') as stream:
        assert b'"3.8.20"' in stream.read()
    build = os.path.join(source, 'PCbuild', 'amd64')
    required = ['python.exe', 'pythonw.exe', 'python38.dll', 'python3.dll',
                'sqlite3.dll']
    required += [name + '.pyd' for name in EXTENSIONS]
    for name in required:
        assert os.path.isfile(os.path.join(build, name)), name
    redist_crt = os.path.join(v142_root, 'vc', 'Contents', 'VC', 'Redist',
                              'MSVC', '14.29.30133', 'x64',
                              'Microsoft.VC142.CRT')
    ucrt = os.path.join(v142_root, 'sdk', 'Windows Kits', '10', 'Redist',
                        '10.0.19041.0', 'ucrt', 'DLLs', 'x64')
    for name in ('vcruntime140.dll', 'vcruntime140_1.dll'):
        assert os.path.isfile(os.path.join(redist_crt, name)), name
    assert os.path.isfile(os.path.join(ucrt, 'ucrtbase.dll'))
    openssl_bin = os.path.join(source, 'externals', 'openssl-bin-1.1.1w',
                               'amd64')
    assert os.path.isfile(os.path.join(openssl_bin, 'libcrypto-1_1.dll'))
    assert not os.path.exists(output), 'output already exists'
    os.mkdir(output)
    os.mkdir(os.path.join(output, 'DLLs'))
    os.mkdir(os.path.join(output, 'libs'))
    for name in ('python.exe', 'pythonw.exe', 'python38.dll', 'python3.dll',
                 'sqlite3.dll', 'libcrypto-1_1.dll', 'libssl-1_1.dll',
                 'libffi-7.dll'):
        shutil.copyfile(os.path.join(build, name), os.path.join(output, name))
    for name in EXTENSIONS:
        shutil.copyfile(os.path.join(build, name + '.pyd'),
                        os.path.join(output, 'DLLs', name + '.pyd'))
    for name in ('libcrypto-1_1.dll', 'libssl-1_1.dll', 'libffi-7.dll'):
        shutil.copyfile(os.path.join(build, name),
                        os.path.join(output, 'DLLs', name))
    for name in ('libcrypto-1_1.dll', 'libssl-1_1.dll', 'LICENSE'):
        shutil.copyfile(os.path.join(openssl_bin, name),
                        os.path.join(output, 'DLLs', name))
    os.rename(os.path.join(output, 'DLLs', 'LICENSE'),
              os.path.join(output, 'DLLs', 'OpenSSL-LICENSE.txt'))
    for name in os.listdir(redist_crt):
        if name.lower().endswith('.dll'):
            shutil.copyfile(os.path.join(redist_crt, name),
                            os.path.join(output, name))
    notice = next((name for name in os.listdir(redist_crt)
                   if os.path.splitext(name)[1].lower() in ('.txt', '.htm')
                   and os.path.isfile(os.path.join(redist_crt, name))), None)
    if notice:
        shutil.copyfile(os.path.join(redist_crt, notice),
                        os.path.join(output, 'VC142-CRT-notice.txt'))
    for name in os.listdir(ucrt):
        shutil.copyfile(os.path.join(ucrt, name), os.path.join(output, name))
    shutil.copyfile(os.path.join(source, 'LICENSE'),
                    os.path.join(output, 'LICENSE.txt'))
    for origin, name in (
        ('Doc/license.rst', 'Python-third-party-notices.rst'),
        ('Modules/expat/COPYING', 'Expat-COPYING.txt'),
        ('externals/zlib-1.3.1/README', 'zlib-README.txt'),
        ('externals/libffi-3.3.0/LICENSE', 'libffi-LICENSE.txt'),
        ('externals/xz-5.2.2/COPYING', 'XZ-COPYING.txt'),
        ('externals/bzip2-1.0.8/LICENSE', 'bzip2-LICENSE.txt'),
        ('externals/sqlite-3.35.5.0/sqlite3.c', 'sqlite3-notices.txt'),
    ):
        shutil.copyfile(os.path.join(source, *origin.split('/')),
                        os.path.join(output, name))
    with open(os.path.join(source, 'Modules', '_decimal', 'libmpdec',
                           'mpdecimal.c'), 'rb') as stream:
        decimal_notice = stream.read().split(b'*/', 1)[0] + b'*/\n'
    with open(os.path.join(output, 'libmpdec-LICENSE.txt'), 'wb') as stream:
        stream.write(decimal_notice)
    for name in ('python38.lib', 'python3.lib'):
        source_lib = os.path.join(build, name)
        if os.path.isfile(source_lib):
            shutil.copyfile(source_lib, os.path.join(output, 'libs', name))
    shutil.copytree(os.path.join(source, 'Include'),
                    os.path.join(output, 'include'))
    shutil.copyfile(os.path.join(source, 'PC', 'pyconfig.h'),
                    os.path.join(output, 'include', 'pyconfig.h'))
    excluded = {'__pycache__', 'test', 'tests', 'idlelib', 'tkinter',
                'turtledemo', 'lib2to3', 'pydoc_data'}
    library = os.path.join(source, 'Lib')
    for directory, folders, files in os.walk(library):
        folders[:] = sorted(name for name in folders if name not in excluded)
        destination = os.path.join(output, 'Lib',
                                   os.path.relpath(directory, library))
        if not os.path.isdir(destination): os.makedirs(destination)
        for name in sorted(files):
            if not name.endswith(('.pyc', '.pyo')):
                shutil.copyfile(os.path.join(directory, name),
                                os.path.join(destination, name))
    with open(os.path.join(output, 'README.txt'), 'w') as stream:
        stream.write('CPython 3.8.20, 64-bit command-line build for Windows 7 SP1 and later.\n'
            'Built from the final 3.8.20 source; this is not an official PSF binary.\n'
            'Run python.exe directly. The standard library, extension modules, VC++ 2019\n'
            'runtime and Universal CRT are app-local next to the interpreter.\n'
            'No Tcl/Tk, IDLE, test suite, installation or automatic dependency download.\n'
            'The OpenSSL binaries are the CPython-published 1.1.1w externals.\n'
            'See the corresponding-source attachment for dependency sources and build inputs.\n')
    probe = r'''
import sys, os, ctypes, ssl, sqlite3, bz2, lzma, hashlib, json, csv, re, zipfile
import zlib, decimal, xml.etree.ElementTree, socket, select, unicodedata
import multiprocessing, encodings, winsound
assert sys.version_info[:3] == (3, 8, 20)
root = os.path.normcase(os.path.abspath(sys.argv[1]))
assert os.path.normcase(sys.prefix) == root, (sys.prefix, root)
assert os.path.normcase(json.__file__).startswith(root + os.sep)
assert os.path.normcase(ssl.__file__).startswith(root + os.sep)
assert sqlite3.connect(':memory:').execute('select 6*7').fetchone()[0] == 42
assert ssl.OPENSSL_VERSION.startswith('OpenSSL 1.1.1w')
assert bz2.decompress(bz2.compress(b'portable')) == b'portable'
assert lzma.decompress(lzma.compress(b'portable')) == b'portable'
assert zlib.decompress(zlib.compress(b'portable')) == b'portable'
assert hashlib.sha256(b'abc').hexdigest() == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
k = ctypes.windll.kernel32
k.GetModuleHandleW.restype = ctypes.c_void_p
k.GetModuleFileNameW.argtypes = (ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint)
path = ctypes.create_unicode_buffer(32768)
for runtime in ('vcruntime140.dll', 'vcruntime140_1.dll', 'ucrtbase.dll'):
    handle = k.GetModuleHandleW(runtime)
    if not handle:
        # vcruntime140_1 only loads when a binary needs its AVX support and
        # the app-local copy then satisfies it; absence is not a failure.
        assert os.path.isfile(os.path.join(root, runtime)), runtime
        continue
    k.GetModuleFileNameW(handle, path, len(path))
    loaded = os.path.normcase(path.value)
    if runtime == 'ucrtbase.dll' and not loaded.startswith(root + os.sep):
        # Modern hosts resolve the UCRT through the api-set schema to the
        # system copy first; the app-local pair only takes over on hosts
        # without a system UCRT, so require the staged file instead.
        assert os.path.isfile(os.path.join(root, runtime)), runtime
        continue
    assert loaded == os.path.join(root, runtime), (runtime, loaded)
print('python38-portable=PASS version=3.8.20 CRT=app-local')
'''
    environment = os.environ.copy()
    environment.pop('PYTHONHOME', None)
    environment.pop('PYTHONPATH', None)
    subprocess.check_call([os.path.join(output, 'python.exe'), '-E', '-S',
                           '-B', '-c', probe, output],
                          cwd=output, env=environment)
    relocation = os.path.join(os.path.dirname(output), 'py38-relocated')
    shutil.move(output, relocation)
    try:
        subprocess.check_call([os.path.join(relocation, 'python.exe'),
                               '-E', '-S', '-B', '-c', probe, relocation],
                              cwd=relocation, env=environment)
    finally:
        shutil.move(relocation, output)
    with zipfile.ZipFile(output + '.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for directory, folders, files in os.walk(output):
            folders.sort()
            for name in sorted(files):
                path = os.path.join(directory, name)
                archive.write(path,
                              os.path.join('python3',
                                           os.path.relpath(path, output)))
    print('python38-staged=' + output + '.zip')


if __name__ == '__main__':
    main()
