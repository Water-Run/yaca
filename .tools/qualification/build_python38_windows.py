#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-10-02
# File: build_python38_windows.py
# Description: Build CPython 3.8.20 x64 with the privately extracted v142 toolchain and MSBuild.

"""Build CPython 3.8.20 x64 using private extractions, without installation.

Run on a Windows host with the std Python 3 interpreter. All toolchain
inputs are produced by fetch_v142_toolchain_windows.py (MSVC 14.29 v142
compiler, CRT, Windows 10 SDK 19041) and fetch_msbuild16_windows.py
(MSBuild 16.11 engine plus the v142 C++ targets); no Visual Studio
installation, registry writes, PATH changes or elevation are involved.
The caller extracts the CPython source and runs PCbuild/get_externals.bat
--no-tkinter beforehand; only the selected source/build directory tree is
modified. The default project set mirrors the Python 3.4.10 toolbox scope
adapted to 3.8: interpreter plus the extension modules the full edition
declares (ssl/sqlite3/bz2/lzma/ctypes and companions).

Arguments: MSBUILD16_ROOT V142_ROOT SOURCE
MSBUILD16_ROOT is the .../msbuild/Contents tree. V142_ROOT is the
fetch_v142_toolchain_windows.py cache directory holding vc/, sdk/ and
sdk-buildtools/. SOURCE is the extracted Python-3.8.20 directory.
"""

from __future__ import print_function
import argparse
import ctypes
import os
import subprocess
import sys


# Runs the build python38 windows command and reports its status.
#@param none No arguments; paths arrive through argparse.
#@return None result No value; builds the pinned CPython 3.8.20 payloads.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('msbuild16')
    parser.add_argument('v142')
    parser.add_argument('source')
    parser.add_argument('--skip-core', action='store_true',
                        help='reuse an already built pythoncore in this tree')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('requires the Windows build host')
    msbuild_contents, v142_root, source = map(os.path.abspath,
                                              (args.msbuild16, args.v142,
                                               args.source))
    with open(os.path.join(source, 'Include', 'patchlevel.h'), 'rb') as stream:
        assert b'"3.8.20"' in stream.read(), 'wrong CPython source version'

    msbuild_root = os.path.join(msbuild_contents, 'MSBuild')
    msbuild_bin = os.path.join(msbuild_root, 'Current', 'Bin')
    msbuild_exe = os.path.join(msbuild_bin, 'MSBuild.exe')
    msvc = os.path.join(v142_root, 'vc', 'Contents', 'VC', 'Tools',
                        'MSVC', '14.29.30133')
    kits = os.path.join(v142_root, 'sdk', 'Windows Kits', '10')
    buildtools_bin = os.path.join(v142_root, 'sdk-buildtools', 'bin',
                                  '10.0.19041.0', 'x64')
    for required in (msbuild_exe,
                     os.path.join(msvc, 'bin', 'Hostx64', 'x64', 'cl.exe'),
                     os.path.join(msvc, 'lib', 'x64', 'libcmt.lib'),
                     os.path.join(msvc, 'lib', 'onecore', 'x64', 'msvcrt.lib'),
                     os.path.join(kits, 'Include', '10.0.19041.0', 'um',
                                  'Windows.h'),
                     os.path.join(kits, 'Lib', '10.0.19041.0', 'ucrt', 'x64',
                                  'ucrt.lib'),
                     os.path.join(buildtools_bin, 'rc.exe'),
                     os.path.join(buildtools_bin, 'mt.exe')):
        assert os.path.isfile(required), 'missing toolchain input: %s' % required

    windows = ctypes.create_unicode_buffer(32768)
    assert ctypes.windll.kernel32.GetWindowsDirectoryW(windows, len(windows))
    winroot = windows.value
    ctypes.windll.kernel32.SetErrorMode(3)
    env = os.environ.copy()
    env['SYSTEMROOT'] = winroot
    env['COMSPEC'] = os.path.join(winroot, 'System32', 'cmd.exe')
    env['PATH'] = os.pathsep.join([
        os.path.join(msvc, 'bin', 'Hostx64', 'x64'), msbuild_bin,
        buildtools_bin, os.path.join(winroot, 'System32')])
    env['INCLUDE'] = os.pathsep.join([
        os.path.join(msvc, 'include'),
        os.path.join(kits, 'Include', '10.0.19041.0', 'ucrt'),
        os.path.join(kits, 'Include', '10.0.19041.0', 'um'),
        os.path.join(kits, 'Include', '10.0.19041.0', 'shared'),
        os.path.join(kits, 'Include', '10.0.19041.0', 'winrt'),
        os.path.join(kits, 'Include', '10.0.19041.0', 'cppwinrt')])
    env['LIB'] = os.pathsep.join([
        os.path.join(msvc, 'lib', 'x64'),
        os.path.join(msvc, 'lib', 'onecore', 'x64'),
        os.path.join(kits, 'Lib', '10.0.19041.0', 'ucrt', 'x64'),
        os.path.join(kits, 'Lib', '10.0.19041.0', 'um', 'x64')])
    for name in ('CL', '_CL_', 'LINK', '_LINK_', 'PYTHONHOME', 'PYTHONPATH',
                 'EXTERNALS_DIR'):
        env.pop(name, None)

    build = os.path.join(source, 'PCbuild')
    properties = {
        'Configuration': 'Release', 'Platform': 'x64',
        'PlatformToolset': 'v142',
        'WindowsTargetPlatformVersion': '10.0.19041.0',
        'WindowsSdkDir': kits + os.sep,
        'WindowsSDKVersion': '10.0.19041.0\\',
        'VCToolsInstallRoot': msvc + os.sep,
        'VCTargetsPath': os.path.join(msbuild_root, 'Microsoft', 'VC', 'v160')
                          + os.sep,
        'UseEnv': 'true', 'TrackFileAccess': 'false',
        'UserRootDir': os.path.join(source, 'yaca-empty-user-props') + os.sep,
        # The private SDK extraction ships no UWP DesignTime UAP.props; the
        # desktop support markers it does ship make the overrides accurate.
        'WindowsSDKInstalled': 'true',
        'WindowsSDK_Desktop_Support': 'true',
    }
    command = [msbuild_exe, '/nologo', '/m:1', '/verbosity:minimal']
    command.extend('/p:' + key + '=' + value
                   for key, value in sorted(properties.items()))

    python = os.path.join(build, 'amd64', 'python.exe')
    probe = ("import sys; assert sys.version_info[:3] == (3,8,20); "
             "print(sys.version)")
    if args.skip_core:
        subprocess.check_call([python, '-E', '-S', '-B', '-c', probe],
                              cwd=source, env=env)
    projects = [] if args.skip_core else ['python']
    projects += ['pythonw', 'python3dll', '_ctypes', '_decimal',
                 '_elementtree', '_multiprocessing', '_overlapped', '_queue',
                 '_socket', 'pyexpat', 'select', 'unicodedata', 'winsound',
                 '_bz2', 'liblzma', '_lzma', 'sqlite3', '_sqlite3',
                 '_ssl', '_hashlib']
    for name in projects:
        print('building=' + name)
        sys.stdout.flush()
        reference_options = [] if name in ('python',) \
            else ['/p:BuildProjectReferences=false']
        subprocess.check_call(command + reference_options
                              + [os.path.join(build, name + '.vcxproj')],
                              cwd=build, env=env)
    subprocess.check_call([python, '-E', '-S', '-B', '-c', probe],
                          cwd=source, env=env)
    print('python38-build=PASS')


if __name__ == '__main__':
    main()
