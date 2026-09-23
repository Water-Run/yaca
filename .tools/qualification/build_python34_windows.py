#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-09-23
# File: build_python34_windows.py
# Description: Build CPython 3.4.10 using a private extracted SDK 7.1, without installation.

"""Build CPython 3.4.10 using a private extracted SDK 7.1, without installation.

Run on Windows using the std Python 2.7 interpreter, under the invoking host's
resource guard. Inputs are produced by prepare_python34.sh and extract_sdk71.py.
Only the selected source/build directory is modified. No registry/PATH writes,
dependency downloads, package installation or process-wide Python kill occur.
"""
from __future__ import print_function
import argparse
import ctypes
import os
import re
import shutil
import subprocess
import sys


# Runs the build python34 windows command and reports its status.
#@param none No arguments.
#@return None result No value; builds pinned portable Python 3.4 inputs.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk')
    parser.add_argument('source')
    parser.add_argument('--core-only', action='store_true')
    parser.add_argument('--skip-core', action='store_true', help='reuse an already verified core in this same source tree')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('requires the Windows build host')
    if args.core_only and args.skip_core:
        parser.error('--core-only and --skip-core are mutually exclusive')
    sdk, source = map(os.path.abspath, (args.sdk, args.source))
    with open(os.path.join(source, 'Include', 'patchlevel.h'), 'rb') as stream:
        assert b'"3.4.10"' in stream.read(), 'wrong CPython source version'
    with open(os.path.join(source, 'PCbuild', 'pythoncore.vcxproj'), 'rb') as stream:
        project = stream.read()
        assert b'$(KillPythonExe)' not in project and b'kill_python.vcxproj' not in project
    windows = ctypes.create_unicode_buffer(32768)
    assert ctypes.windll.kernel32.GetWindowsDirectoryW(windows, len(windows))
    winroot = windows.value.encode('mbcs') if sys.version_info[0] == 2 else windows.value
    ctypes.windll.kernel32.SetErrorMode(3)
    vs = os.path.join(sdk, 'Program Files', 'Microsoft Visual Studio 10.0')
    vc = os.path.join(vs, 'VC')
    ws = os.path.join(sdk, 'Program Files', 'Microsoft SDKs', 'Windows', 'v7.1')
    framework = os.path.join(winroot, 'Microsoft.NET', 'Framework', 'v4.0.30319')
    linker = os.path.join(source, 'yaca-private-linker')
    if not os.path.isdir(linker):
        os.mkdir(linker)
    shutil.copyfile(os.path.join(vc, 'bin', 'link.exe'), os.path.join(linker, 'link.exe'))
    # SDK 7.1's cvtres requires CLR 4.0's private CRT. A build host updated
    # to .NET 4.5 may no longer provide it. Use that host's matching .NET
    # converter next to this private linker; do not replace system/SDK files.
    shutil.copyfile(os.path.join(framework, 'cvtres.exe'), os.path.join(linker, 'cvtres.exe'))
    sdk_targets = os.path.join(sdk, 'Program Files', 'MSBuild', 'Microsoft.Cpp', 'v4.0')
    targets = os.path.join(source, 'yaca-sdk-targets')
    # Recreate each private input from the SDK on every invocation. An earlier
    # failed copy or rewrite must not make a partial directory look prepared.
    assert os.path.isdir(sdk_targets), 'SDK build targets are missing'
    assemblies = {}
    for directory, _, files in os.walk(sdk_targets):
        destination = os.path.join(targets, os.path.relpath(directory, sdk_targets))
        if not os.path.isdir(destination): os.makedirs(destination)
        for name in files:
            shutil.copyfile(os.path.join(directory, name), os.path.join(destination, name))
            if name.lower().startswith('microsoft.build.cpptasks.') and name.endswith('.dll'):
                assemblies[name[:-4].lower()] = os.path.join(destination, name)
    # MSI normally registers these assemblies in the GAC. Resolve this
    # private copy explicitly instead of installing into the build host.
    pattern = r'AssemblyName="(Microsoft\.Build\.CppTasks\.[^,"]+),[^"]*"'
    for directory, _, files in os.walk(targets):
        for name in files:
            if not name.endswith('.targets'): continue
            path = os.path.join(directory, name)
            with open(path, 'rb') as stream: original = stream.read()
            # Rewrites an assembly reference to its private SDK DLL path.
            #@param match re.Match AssemblyName attribute matched in a target file.
            #@return str AssemblyFile attribute with XML-escaped path.
            changed = re.sub(pattern, lambda match: 'AssemblyFile="' +
                assemblies[match.group(1).lower()].replace('&', '&amp;') + '"', original)
            if changed != original:
                with open(path, 'wb') as stream: stream.write(changed)
    common = assemblies['microsoft.build.cpptasks.common']
    for key, path in assemblies.items():
        destination = os.path.join(os.path.dirname(path), os.path.basename(common))
        if os.path.normcase(destination) != os.path.normcase(common):
            shutil.copyfile(common, destination)
    env = os.environ.copy()
    env['SYSTEMROOT'] = winroot
    env['COMSPEC'] = os.path.join(winroot, 'System32', 'cmd.exe')
    env['PATH'] = ';'.join([os.path.join(vc, 'bin'), os.path.join(vs, 'Common7', 'IDE'),
        os.path.join(sdk, 'Win', 'System'), os.path.join(ws, 'Bin'), framework,
        os.path.join(winroot, 'System32')])
    env['INCLUDE'] = ';'.join([os.path.join(vc, 'include'), os.path.join(ws, 'Include')])
    env['LIB'] = ';'.join([os.path.join(vc, 'lib'), os.path.join(ws, 'Lib')])
    for name in ('CL', '_CL_', 'LINK', '_LINK_', 'PYTHONHOME', 'PYTHONPATH'):
        env.pop(name, None)
    build = os.path.join(source, 'PCbuild')
    userprops = os.path.join(source, 'yaca-empty-user-props')
    if not os.path.isdir(userprops): os.mkdir(userprops)
    properties = {
        'Configuration': 'Release', 'Platform': 'Win32', 'UseEnv': 'true',
        'PlatformToolset': 'v100', 'VCTargetsPath': targets + os.sep,
        'VCInstallDir': vc + os.sep, 'VSInstallDir': vs + os.sep,
        'WindowsSdkDir': ws + os.sep, 'FrameworkDir': framework + os.sep,
        'FrameworkSdkDir': ws + os.sep, 'FrameworkVersion': 'v4.0.30319',
        'UserRootDir': userprops + os.sep, 'SolutionDir': build + os.sep,
        'TrackFileAccess': 'false',
        'CLToolPath': os.path.join(vc, 'bin') + os.sep,
        'LinkToolPath': linker + os.sep,
        'LibToolPath': os.path.join(vc, 'bin') + os.sep,
        'RCToolPath': os.path.join(ws, 'Bin') + os.sep,
        'MtToolPath': os.path.join(ws, 'Bin') + os.sep,
    }
    command = [os.path.join(framework, 'MSBuild.exe'), '/nologo', '/m:1', '/verbosity:minimal']
    command.extend('/p:' + key + '=' + value for key, value in sorted(properties.items()))
    python = os.path.join(build, 'python.exe')
    probe = "import sys; assert sys.version_info[:3] == (3,4,10); print(sys.version)"
    if args.skip_core:
        subprocess.check_call([python, '-E', '-S', '-B', '-c', probe], cwd=source, env=env)
    projects = [] if args.skip_core else ['python']
    if not args.core_only:
        projects += ['pythonw', 'python3dll', '_ctypes', '_decimal', '_elementtree',
            '_multiprocessing', '_socket', 'pyexpat', 'select', 'unicodedata',
            'winsound', '_bz2', '_lzma', 'sqlite3', '_sqlite3', 'ssl', '_ssl', '_hashlib']
    for name in projects:
        print('building=' + name)
        sys.stdout.flush()
        reference_options = [] if name == 'python' else ['/p:BuildProjectReferences=false']
        subprocess.check_call(command + reference_options + [name + '.vcxproj'], cwd=build, env=env)
    subprocess.check_call([python, '-E', '-S', '-B', '-c', probe], cwd=source, env=env)
    print('python34-build=PASS scope=' + ('core' if args.core_only else 'toolbox'))


if __name__ == '__main__':
    main()
