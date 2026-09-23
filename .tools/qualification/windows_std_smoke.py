#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-09-23
# File: windows_std_smoke.py
# Description: Exercise a relocated Windows std package (Python 2.7 or 3 build-host driver).

"""Exercise a relocated Windows std package (Python 2.7 or 3 build-host driver).

Network checks are opt-in and require an explicitly trusted SSH host fingerprint.
No credentials are sent. All sample files stay in a disposable temporary directory.
"""

from __future__ import print_function

import argparse
import ctypes
import os
import shutil
import subprocess
import tempfile
import threading


# Runs the windows std smoke command and reports its status.
#@param none No arguments.
#@return None result No value; assertions exercise bundled Python and SSH tools.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package")
    parser.add_argument("--ssh-host")
    parser.add_argument("--ssh-host-key")
    parser.add_argument("--https-url")
    args = parser.parse_args()
    if bool(args.ssh_host) != bool(args.ssh_host_key):
        parser.error("SSH checks need both the host and its trusted fingerprint")
    root = os.path.abspath(args.package)
    ctypes.windll.kernel32.SetErrorMode(3)
    work = tempfile.mkdtemp(prefix="yaca std test ")

    # Runs the selected command and checks its expected output.
    #@param arguments list[str] Argument vector for the child command.
    #@param expected object Expected observation or child exit state.
    #@return tuple outcome Child exit code and captured output streams.
    def run(arguments, expected=0):
        child = subprocess.Popen(arguments, cwd=work, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        timer = threading.Timer(30, child.kill)
        timer.start()
        try:
            output, error = child.communicate()
        finally:
            timer.cancel()
        if expected is not None:
            assert child.returncode == expected, (arguments[0], child.returncode, output, error)
        return child.returncode, output, error

    # Resolves one bundled executable inside the adjacent tools directory.
    #@param directory Path Directory whose Context entries are listed.
    #@param program object The program supplied to this proof operation.
    #@return str path Bundled executable path under the adjacent tools directory.
    def tool(directory, program):
        return os.path.join(root, "tools", directory, program)

    try:
        python_root = os.path.join(root, "tools", "python2")
        probe = (
            "import sys,os,json,csv,re,sqlite3,ctypes,hashlib,zipfile,ssl,bsddb,encodings; "
            "assert sys.version_info[:3]==(2,7,18); "
            "expected=os.path.normcase(os.path.abspath(sys.argv[1])); "
            "assert os.path.normcase(sys.prefix)==expected,(sys.prefix,expected); "
            "assert all(os.path.normcase(m.__file__).startswith(expected+os.sep) "
            "for m in (json,csv,re,sqlite3,ctypes,hashlib,zipfile,ssl,bsddb,encodings)); "
            "assert sqlite3.connect(':memory:').execute('select 6*7').fetchone()[0]==42; "
            "print('python2-relocated=PASS')"
        )
        _, output, _ = run([tool("python2", "python.exe"), "-E", "-S", "-B", "-c", probe, python_root])
        assert b"python2-relocated=PASS" in output
        print("python2-relocated=PASS")
        for name in ("plink", "pscp", "psftp"):
            _, output, error = run([tool("ssh", name + ".exe"), "-V"])
            assert b"Release 0.85" in output + error
        if args.ssh_host:
            plink = tool("ssh", "plink.exe")
            command = [plink, "-v", "-ssh", "-batch", "-noagent", "-noshare", "-hostkey"]
            tail = ["-l", "yaca-smoke-no-credentials", args.ssh_host, "exit"]
            code, _, error = run(command + [args.ssh_host_key] + tail, expected=None)
            assert code != 0 and args.ssh_host_key.encode("ascii") in error and b"Using username" in error, error
            print("ssh-verified-host-key-handshake=PASS credentials=none")
            code, _, error = run(command + ["SHA256:" + "A" * 43] + tail, expected=None)
            assert code != 0 and b"host key" in error.lower() and b"manually" in error.lower(), error
            print("ssh-wrong-host-key-rejected=PASS")
        if args.https_url:
            _, output, _ = run([tool("curl", "curl.exe"), "--fail", "--silent", "--show-error",
                "--connect-timeout", "10", "--max-time", "20", "--cacert", tool("curl", "cacert.pem"),
                "--output", "NUL", "--write-out", "%{http_code}", args.https_url])
            assert output == b"200", output
            print("curl-verified-https=PASS HTTP=200")
        sample = b"portable archive roundtrip\r\n" * 30
        with open(os.path.join(work, "sample.txt"), "wb") as stream:
            stream.write(sample)
        run([tool("7zip", "7za.exe"), "a", "-t7z", "sample.7z", "sample.txt"])
        run([tool("7zip", "7za.exe"), "x", "-ounpacked", "sample.7z"])
        with open(os.path.join(work, "unpacked", "sample.txt"), "rb") as stream:
            assert stream.read() == sample
        print("7zip-roundtrip=PASS")
    finally:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
