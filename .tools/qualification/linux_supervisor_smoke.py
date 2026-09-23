#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-09-23
# File: linux_supervisor_smoke.py
# Description: Exercise native Linux process ownership, including abrupt parent death.

"""Exercise native Linux process ownership, including abrupt parent death.

Run under the repository resource guard with a new scratch directory. Only the
Lua process created here is killed; test descendants have finite lifetimes.
"""
from __future__ import print_function
import argparse
import ctypes
import errno
import os
import select
import subprocess
import sys
import time


#@class Timespec Owns the linux supervisor smoke state and its resource lifetime.
class Timespec(ctypes.Structure):
    _fields_ = [('seconds', ctypes.c_long), ('nanoseconds', ctypes.c_long)]


libc = ctypes.CDLL(None, use_errno=True)


# Checks now in linux supervisor smoke.
#@param none No arguments.
#@return float seconds Monotonic time from the native clock port.
def now():
    value = Timespec()
    assert libc.clock_gettime(1, ctypes.byref(value)) == 0
    return value.seconds + value.nanoseconds / 1000000000.0


# Checks wait in linux supervisor smoke.
#@param child object The child supplied to this proof operation.
#@param seconds float Maximum wait time in seconds.
#@return int|None status Child exit status after the bounded wait.
def wait(child, seconds):
    deadline = now() + seconds
    while child.poll() is None and now() < deadline:
        time.sleep(0.01)
    if child.poll() is None:
        child.kill()
        child.wait()
        raise AssertionError('probe process exceeded its deadline')
    return child.returncode


# Checks alive in linux supervisor smoke.
#@param pid int Process identity inspected through procfs.
#@return bool running Whether the selected PID remains live outside zombie state.
def alive(pid):
    try:
        with open('/proc/{}/stat'.format(pid)) as stream:
            state = stream.read().rsplit(')', 1)[1].split()[0]
        return state != 'Z'
    except IOError as error:
        if error.errno not in (errno.ENOENT, errno.ESRCH):
            raise
        return False


# Runs the linux supervisor smoke command and reports its status.
#@param none No arguments.
#@return None result No value; assertions verify process-tree cancellation.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('lua', 'source', 'native', 'scratch'):
        parser.add_argument(name)
    args = parser.parse_args()
    lua, source, native, scratch = (os.path.realpath(getattr(args, name))
        for name in ('lua', 'source', 'native', 'scratch'))
    os.mkdir(scratch)
    script = source + '/.tools/qualification/linux_supervisor_smoke.lua'
    command = [lua, '-E', script, source, native, scratch]
    assert wait(subprocess.Popen(command), 25) == 0
    child = subprocess.Popen(command + ['parent-death'], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, universal_newlines=True)
    try:
        assert select.select([child.stdout], [], [], 3)[0], 'parent did not start its descendant'
        line = child.stdout.readline().strip()
        assert line.startswith('ready=') and line[6:].isdigit(), line
        descendant = int(line[6:])
        assert alive(descendant), 'descendant did not start'
        child.kill()
        wait(child, 3)
        deadline = now() + 2
        while alive(descendant) and now() < deadline:
            time.sleep(0.01)
        assert not alive(descendant), 'abrupt parent death left a descendant running'
        print('linux-parent-death=PASS detached-descendant-stopped')
        sys.stdout.flush()
    finally:
        if child.poll() is None:
            child.kill()
            wait(child, 3)
        child.stdout.close()
        child.stderr.close()


if __name__ == '__main__':
    main()
