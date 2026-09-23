#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-09-23
# File: stage_python34_windows.py
# Description: Stage the private CPython 3.4.10 build as a portable command-line toolbox.

"""Stage the private CPython 3.4.10 build as a portable command-line toolbox.

Run on Windows with Python 2.7. The CRT and its notice come from the verified
official Python 3.4.4 MSI; no Python 3.4.4 interpreter is copied. No installation,
registry changes or PATH changes are performed. The destination must be new.
"""
from __future__ import print_function
import argparse
import hashlib
import os
import shutil
import subprocess
import zipfile


EXTENSIONS = ('_bz2', '_ctypes', '_decimal', '_elementtree', '_hashlib', '_lzma',
              '_multiprocessing', '_socket', '_sqlite3', '_ssl', 'pyexpat',
              'select', 'unicodedata', 'winsound')


# Runs the stage python34 windows command and reports its status.
#@param none No arguments.
#@return None result No value; stages the verified portable Python 3.4 tree.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'crt', 'crt_notice', 'lzma_notice', 'output'):
        parser.add_argument(name)
    args = parser.parse_args()
    source, crt, notice, lzma_notice, output = [os.path.abspath(getattr(args, name))
        for name in ('source', 'crt', 'crt_notice', 'lzma_notice', 'output')]
    if os.name != 'nt':
        parser.error('the build and relocation probe require Windows')
    with open(os.path.join(source, 'Include', 'patchlevel.h'), 'rb') as stream:
        assert b'"3.4.10"' in stream.read()
    build = os.path.join(source, 'PCbuild')
    required = ['python.exe', 'pythonw.exe', 'python34.dll', 'python3.dll',
                'sqlite3.dll', 'python34.lib', 'python3.lib']
    required += [name + '.pyd' for name in EXTENSIONS]
    for name in required:
        assert os.path.isfile(os.path.join(build, name)), name
    assert os.path.isfile(crt) and os.path.isfile(notice)
    with open(crt, 'rb') as stream:
        assert hashlib.sha256(stream.read()).hexdigest() == '60c06e0fa4449314da3a0a87c1a9d9577df99226f943637e06f61188e5862efa'
    assert os.path.isfile(lzma_notice)
    assert not os.path.exists(output), 'output already exists'
    os.mkdir(output)
    os.mkdir(os.path.join(output, 'DLLs'))
    os.mkdir(os.path.join(output, 'libs'))
    for name in required:
        directory = 'libs' if name.endswith('.lib') else (
            'DLLs' if name.endswith('.pyd') or name == 'sqlite3.dll' else '')
        shutil.copyfile(os.path.join(build, name), os.path.join(output, directory, name))
    shutil.copyfile(crt, os.path.join(output, 'msvcr100.dll'))
    shutil.copyfile(notice, os.path.join(output, 'Microsoft-CRT-distribution-notice.txt'))
    shutil.copyfile(os.path.join(source, 'LICENSE'), os.path.join(output, 'LICENSE.txt'))
    shutil.copyfile(lzma_notice, os.path.join(output, 'XZ-COPYING.txt'))
    for origin, name in (
        ('Doc/license.rst', 'Python-third-party-notices.rst'),
        ('Modules/expat/COPYING', 'Expat-COPYING.txt'),
        ('Modules/zlib/README', 'zlib-README.txt'),
        ('Modules/_ctypes/libffi_msvc/LICENSE', 'libffi-LICENSE.txt'),
    ):
        shutil.copyfile(os.path.join(source, *origin.split('/')), os.path.join(output, name))
    with open(os.path.join(source, 'Modules', '_decimal', 'libmpdec', 'mpdecimal.c'), 'rb') as stream:
        decimal_notice = stream.read().split(b'*/', 1)[0] + b'*/\n'
    with open(os.path.join(output, 'libmpdec-LICENSE.txt'), 'wb') as stream:
        stream.write(decimal_notice)
    shutil.copyfile(os.path.join(source, 'externals', 'openssl-1.0.2k', 'LICENSE'),
                    os.path.join(output, 'OpenSSL-LICENSE.txt'))
    shutil.copyfile(os.path.join(source, 'externals', 'bzip2-1.0.6', 'LICENSE'),
                    os.path.join(output, 'bzip2-LICENSE.txt'))
    shutil.copytree(os.path.join(source, 'Include'), os.path.join(output, 'include'))
    shutil.copyfile(os.path.join(source, 'PC', 'pyconfig.h'),
                    os.path.join(output, 'include', 'pyconfig.h'))
    excluded = {'__pycache__', 'test', 'tests', 'idlelib', 'tkinter', 'turtledemo'}
    library = os.path.join(source, 'Lib')
    for directory, folders, files in os.walk(library):
        folders[:] = sorted(name for name in folders if name not in excluded)
        destination = os.path.join(output, 'Lib', os.path.relpath(directory, library))
        if not os.path.isdir(destination): os.makedirs(destination)
        for name in sorted(files):
            if not name.endswith(('.pyc', '.pyo')):
                shutil.copyfile(os.path.join(directory, name), os.path.join(destination, name))
    with open(os.path.join(output, 'README.txt'), 'w') as stream:
        stream.write('CPython 3.4.10, 32-bit command-line build for Windows XP and later.\n'
            'Built from the final 3.4.10 source; this is not an official PSF binary.\n'
            'Run python.exe directly. The standard library, extension modules and CRT are local.\n'
            'No Tcl/Tk, IDLE, test suite, installation or automatic dependency download.\n'
            'Headers and import libraries are included for development.\n'
            'The unchanged Microsoft CRT and its distribution notice originate in the official\n'
            'Python 3.4.4 MSI. Only that CRT is reused; all Python binaries are built as 3.4.10.\n'
            'See the corresponding-source attachment for dependency sources and build inputs.\n')
    probe = r'''
import sys, os, ctypes, ssl, sqlite3, bz2, lzma, hashlib, json, multiprocessing, zlib
import decimal, xml.etree.ElementTree, socket, select, unicodedata, winsound
assert sys.version_info[:3] == (3, 4, 10)
root = os.path.normcase(os.path.abspath(sys.argv[1]))
assert os.path.normcase(sys.prefix) == root, (sys.prefix, root)
assert os.path.normcase(json.__file__).startswith(root + os.sep)
assert os.path.normcase(ssl.__file__).startswith(root + os.sep)
assert sqlite3.connect(':memory:').execute('select 6*7').fetchone()[0] == 42
assert ssl.OPENSSL_VERSION.startswith('OpenSSL 1.0.2k')
assert bz2.decompress(bz2.compress(b'portable')) == b'portable'
assert lzma.decompress(lzma.compress(b'portable')) == b'portable'
assert zlib.decompress(zlib.compress(b'portable')) == b'portable'
assert hashlib.sha256(b'abc').hexdigest() == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
k = ctypes.windll.kernel32
k.GetModuleHandleW.restype = ctypes.c_void_p
k.GetModuleFileNameW.argtypes = (ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint)
path = ctypes.create_unicode_buffer(32768)
assert k.GetModuleFileNameW(k.GetModuleHandleW('msvcr100.dll'), path, len(path))
assert os.path.normcase(path.value) == os.path.join(root, 'msvcr100.dll'), path.value
print('python34-portable=PASS version=3.4.10 CRT=app-local modules=14')
'''
    environment = os.environ.copy()
    environment.pop('PYTHONHOME', None)
    environment.pop('PYTHONPATH', None)
    subprocess.check_call([os.path.join(output, 'python.exe'), '-E', '-S', '-B', '-c',
                           probe, output], cwd=output, env=environment)
    with zipfile.ZipFile(output + '.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for directory, folders, files in os.walk(output):
            folders.sort()
            for name in sorted(files):
                path = os.path.join(directory, name)
                archive.write(path, os.path.join('python3', os.path.relpath(path, output)))
    print('python34-staged=' + output + '.zip')


if __name__ == '__main__':
    main()
