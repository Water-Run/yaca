# Author: WaterRun
# Date: 2026-09-23
# File: windows_inherited_smoke.py
# Description: Run native publication checks against an actual inherited NTFS DACL.

"""Run native publication checks against an actual inherited NTFS DACL.

Python 2.7/3.x, Windows XP or later. Creates only the requested new fixture
directory. Does not require PowerShell or change its execution policy.
"""
from __future__ import print_function

import argparse
import ctypes
from ctypes import wintypes as w
import os
import subprocess


# Stages pinned compatibility inputs in an isolated output root.
#@param path Path|str Input file or package path under inspection.
#@return None result No value; writes inherited launch inputs for the smoke test.
def prepare(path):
    a = ctypes.WinDLL('advapi32', use_last_error=True)
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    pointer = ctypes.c_void_p
    pp = ctypes.POINTER(pointer)
    a.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [
        w.LPCWSTR, w.DWORD, pp, ctypes.POINTER(w.DWORD)]
    a.ConvertStringSecurityDescriptorToSecurityDescriptorW.restype = w.BOOL
    a.GetSecurityDescriptorDacl.argtypes = [pointer, ctypes.POINTER(w.BOOL), pp,
                                           ctypes.POINTER(w.BOOL)]
    a.GetSecurityDescriptorDacl.restype = w.BOOL
    a.SetNamedSecurityInfoW.argtypes = [w.LPWSTR, ctypes.c_int, w.DWORD,
                                      pointer, pointer, pointer, pointer]
    a.SetNamedSecurityInfoW.restype = w.DWORD
    a.GetNamedSecurityInfoW.argtypes = [w.LPCWSTR, ctypes.c_int, w.DWORD,
                                      pp, pp, pp, pp, pp]
    a.GetNamedSecurityInfoW.restype = w.DWORD
    a.GetSecurityDescriptorControl.argtypes = [pointer, ctypes.POINTER(w.WORD),
                                               ctypes.POINTER(w.DWORD)]
    a.GetSecurityDescriptorControl.restype = w.BOOL
    a.GetAce.argtypes = [pointer, w.DWORD, pp]
    a.GetAce.restype = w.BOOL
    k.LocalFree.argtypes = [pointer]
    k.LocalFree.restype = pointer

    # Raises on a failed proof assertion with a scenario-specific message.
    #@param ok object The ok supplied to this proof operation.
    #@return None No value; the operation updates proof state or raises on failure.
    def check(ok):
        if not ok:
            raise ctypes.WinError(ctypes.get_last_error())

    descriptor = pointer()
    # The file is public test data. An explicit read ACE makes its DACL
    # different from the native temporary, while preserving parent inheritance.
    check(a.ConvertStringSecurityDescriptorToSecurityDescriptorW(
        u'D:(A;;GR;;;WD)', 1, ctypes.byref(descriptor), None))
    try:
        present, defaulted, dacl = w.BOOL(), w.BOOL(), pointer()
        check(a.GetSecurityDescriptorDacl(descriptor, ctypes.byref(present),
                                          ctypes.byref(dacl), ctypes.byref(defaulted)))
        assert present.value and dacl.value
        status = a.SetNamedSecurityInfoW(path, 1, 0x20000004, None, None, dacl, None)
        if status:
            raise ctypes.WinError(status)
    finally:
        k.LocalFree(descriptor)

    descriptor, dacl = pointer(), pointer()
    status = a.GetNamedSecurityInfoW(path, 1, 4, None, None, ctypes.byref(dacl),
                                     None, ctypes.byref(descriptor))
    if status:
        raise ctypes.WinError(status)
    try:
        control, revision = w.WORD(), w.DWORD()
        check(a.GetSecurityDescriptorControl(descriptor, ctypes.byref(control),
                                              ctypes.byref(revision)))
        assert control.value & 0x400, 'fixture lacks SE_DACL_AUTO_INHERITED'
        assert not control.value & 0x1000, 'fixture inheritance is protected'
        assert dacl.value, 'fixture lacks a DACL'
        # ACL header: BYTE revision, BYTE reserved, WORD size, WORD count.
        count = w.WORD.from_address(dacl.value + 4).value
        inherited = 0
        for index in range(count):
            ace = pointer()
            check(a.GetAce(dacl, index, ctypes.byref(ace)))
            inherited += bool(ctypes.c_ubyte.from_address(ace.value + 1).value & 0x10)
        assert inherited > 0, 'fixture lacks an inherited ACE'
        print('windows-inherited-fixture=PASS control=%04x inherited=%d' %
              (control.value, inherited))
    finally:
        k.LocalFree(descriptor)


# Runs the windows inherited smoke command and reports its status.
#@param none No arguments.
#@return int status Exit status of the inherited-handle child invocation.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inner')
    parser.add_argument('native_directory')
    parser.add_argument('probe')
    parser.add_argument('root', help='new directory on NTFS; must not already exist')
    parser.add_argument('--arch', choices=('x86', 'x86_64'), default='x86')
    args = parser.parse_args()
    root = os.path.abspath(args.root)
    if not isinstance(root, type(u'')):
        root = root.decode('mbcs')
    os.mkdir(root)
    path = os.path.join(root, 'direct-inherited-smoke.txt')
    with open(path, 'wb') as output:
        output.write(b'inherited target\n')
    prepare(path)
    cpath = os.path.abspath(args.native_directory).replace('\\', '/') + '/?.dll'
    # Quote a Lua string, including paths containing apostrophes.
    cpath = cpath.replace('\\', '\\\\').replace("'", "\\'")
    return subprocess.call([args.inner, '--lua', '-E', '-e',
                            "package.cpath='%s'" % cpath, args.probe, root,
                            args.arch, '--inherited-fixture'])


if __name__ == '__main__':
    raise SystemExit(main())
