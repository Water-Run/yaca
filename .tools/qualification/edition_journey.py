#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: edition_journey.py
# Description: Run isolated offline Linux edition journeys with byte audits, a real PTY and portable-core checks.

"""Exercise a final Linux clean/std/full ZIP and its companion notices.

Only a fresh temporary child of scratch is modified. Existing scratch contents
are retained. This offline core journey does not qualify online or target work.
"""

import argparse
import errno
import json
import os
import pathlib
import platform
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time
import zipfile

import audit_editions as audit


# Execute one finite offline command with either captured pipes or a controlling PTY.
#@param command list[str] Executable followed by literal argument words, never shell code.
#@param directory Path Existing working directory owned by the isolated journey.
#@param terminal bool True to run under a real POSIX controlling terminal.
#@return dict Process exit code and UTF-8 diagnostic output with terminal controls retained.
#@error Raises on launch failure, a 120-second timeout or PTY output above two MiB.
#@effect Starts and reaps a child; timeout/failure terminates the owned PTY process group.
def run_command(command, directory, terminal=False):
    if not terminal:
        result = subprocess.run(command, cwd=directory, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        return {"exit_code": result.returncode, "output": result.stdout.decode("utf-8", "replace")}
    import fcntl
    import pty
    import struct
    import termios
    pid, master = pty.fork()
    if pid == 0:
        try:
            os.chdir(directory)
            os.execv(command[0], command)
        except OSError:
            os._exit(127)
    output = bytearray()
    reaped = False
    try:
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        deadline = time.monotonic() + 120
        while True:
            remaining = deadline - time.monotonic()
            audit.require(remaining > 0, "PTY command exceeded 120 seconds")
            if not select.select([master], [], [], min(remaining, 0.5))[0]:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                chunk = b""
            if not chunk:
                break
            output.extend(chunk)
            audit.require(len(output) <= 2 * 1024 * 1024, "PTY output exceeded two MiB")
        while True:
            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                reaped = True
                break
            audit.require(time.monotonic() < deadline, "PTY child did not exit after closing output")
            time.sleep(0.01)
        return {"exit_code": os.waitstatus_to_exitcode(status), "output": output.decode("utf-8", "replace")}
    finally:
        os.close(master)
        if not reaped:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)


# Extract an audited runtime ZIP into a new directory and preserve executable modes.
#@param path Path Runtime ZIP whose paths were admitted by audit_pair.
#@param destination Path Absent installation directory inside the owned temporary root.
#@return None No value; all regular payload files are created with exclusive writes.
#@error Raises on extraction errors or a pre-existing destination.
#@effect Creates directories and payload files only beneath destination.
def extract(path, destination):
    destination.mkdir()
    with zipfile.ZipFile(path) as archive:
        for item in archive.infolist():
            name = audit.PACKAGING.safe_destination(item.filename)
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output, 1024 * 1024)
            target.chmod((item.external_attr >> 16) & 0o777)


# Accept a Stage 1 transcript only when the complete offline stage ran without failures.
#@param observed dict Captured exit_code and output from the PTY command.
#@return bool True for a passed stage or a partial stage containing only warnings.
def stage1_passed(observed):
    text = observed["output"]
    match = re.search(r"outcome=(passed|partial)\b", text)
    if not match:
        return False
    expected_code = 0 if match[1] == "passed" else 1
    return observed["exit_code"] == expected_code and not re.search(r"\bFAILED\b", text) and all(
        re.search(pattern, text) for pattern in (
            r"completed-stage=1\b", r"online-requests=0\b", r"auto-fixes=0\b"))


# Run one candidate's offline core journey and retain its precise artifact binding.
#@param package Path Explicit Linux runtime ZIP.
#@param notices Path Explicit matching companion ZIP.
#@param scratch Path Existing or new parent for a uniquely owned temporary directory.
#@return dict Offline observations, host identity and unqualified artifact checksums.
#@error Raises for unsupported hosts, damaged archives or any failed journey step.
#@effect Extracts and executes candidate bytes; all owned installation/data/tool files are removed on exit.
def journey(package, notices, scratch):
    audit.require(platform.system() == "Linux" and platform.machine() in ("x86_64", "amd64"),
                  "offline driver requires a Linux x86_64 host")
    binding = audit.audit_pair(package, notices)
    audit.require(binding["target"] == "linux-x86_64", "runtime target does not match the Linux host")
    steps = [{"id": "package-integrity", "passed": True}]
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="yaca-journey-", dir=scratch) as temporary:
        owned = pathlib.Path(temporary).resolve()
        install = owned / "installation with spaces"
        work = owned / "workspace"
        work.mkdir()
        extract(package, install)
        audit.require(audit.PACKAGING.digest(package) == binding["archive_sha256"], "archive changed before extraction completed")
        binary = install / "yaca"
        audit.require(audit.PACKAGING.digest(binary) == binding["core_sha256"], "extracted core SHA-256 differs")
        steps.append({"id": "extract", "passed": True})
        observed = run_command([str(binary), "--version"], work)
        expected_version=binding['version'].removesuffix('-preview')
        audit.require(observed["exit_code"] == 0 and
                      "yaca "+expected_version+" (linux-x86_64)" in observed["output"], "version did not match target")
        steps.append({"id": "version", "passed": True, **observed})
        observed = run_command([str(binary), "--status"], work)
        audit.require(observed["exit_code"] != 0 and "TtyRequired" in observed["output"]
                      and not (install / "__yaca__").exists() and not list(work.iterdir()),
                      "non-TTY status did not refuse with zero writes")
        steps.append({"id": "non-tty-no-writes", "passed": True, **observed})
        observed = run_command([str(binary), "--lua", "-E", "-e", "print(6*7)"], work)
        audit.require(observed["exit_code"] == 0 and observed["output"].strip() == "42", "embedded Lua failed")
        steps.append({"id": "embedded-lua", "passed": True, **observed})
        (install / "__yaca__").mkdir()
        observed = run_command([str(binary), "--self-test", "--through-stage", "1"], work, terminal=True)
        audit.require(stage1_passed(observed), "Stage 1 did not complete cleanly: " + observed["output"])
        steps.append({"id": "selftest-stage1", "passed": True, **observed})
        tools = install / "tools"
        if tools.exists():
            tools.rename(owned / "detached-tools")
        observed = run_command([str(binary), "--version"], work)
        lua = run_command([str(binary), "--lua", "-E", "-e", "print(6*7)"], work)
        audit.require(observed["exit_code"] == 0 and lua["exit_code"] == 0 and lua["output"].strip() == "42",
                      "core depends on optional tools")
        steps.append({"id": "without-tools", "passed": True})
        if (owned / "detached-tools").exists():
            (owned / "detached-tools").rename(tools)
        moved = owned / "moved installation"
        install.rename(moved)
        binary = moved / "yaca"
        observed = run_command([str(binary), "--version"], work)
        lua = run_command([str(binary), "--lua", "-E", "-e", "print(6*7)"], work)
        audit.require(observed["exit_code"] == 0 and lua["exit_code"] == 0 and lua["output"].strip() == "42"
                      and audit.PACKAGING.digest(binary) == binding["core_sha256"], "moved core failed")
        steps.append({"id": "move", "passed": True})
    steps.append({"id": "uninstall", "passed": True})
    audit.require(not owned.exists(), "journey-owned directory remained after uninstall")
    steps.append({"id": "verify-no-residue", "passed": True})
    return {"schema": "yaca-edition-journey-v1", "scope": "offline-core",
            "qualification": "pending", "release_authorized": False,
            "host": platform.platform(), "artifact": binding, "steps": steps,
            "pending": ["first-configuration", "chat-tool-turn", "restore", "upgrade", "target-tool-runtime"]}


# Execute the explicit offline journey CLI, refusing unsupported online work before effects.
#@param none No arguments; reads the process command line.
#@return None No value; nonzero exit records a failed or unsupported journey.
#@effect Reads archives, runs the isolated candidate and optionally creates a new JSON report.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=pathlib.Path)
    parser.add_argument("package", type=pathlib.Path)
    parser.add_argument("target", choices=("win32-x86", "win64-x86_64", "linux-x86_64"))
    parser.add_argument("scratch", type=pathlib.Path)
    parser.add_argument("--notices", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    parser.add_argument("--i-accept-online-journey", type=pathlib.Path)
    args = parser.parse_args()
    if args.i_accept_online_journey:
        parser.error("online steps are not executed by this driver; use agent_terminal_smoke.py --online on the configured target")
    if args.target != "linux-x86_64":
        parser.error("runtime target does not match the Linux driver; audit Windows ZIPs with audit_editions.py")
    if args.repo.resolve() != audit.ROOT:
        parser.error("repo must identify the repository containing this driver")
    notices = args.notices or args.package.with_name(args.package.stem + "-notices.zip")
    if args.report and args.report.exists():
        parser.error("report path already exists")
    try:
        report = journey(args.package.absolute(), notices.absolute(), args.scratch.resolve())
        if args.report:
            with args.report.open("x", encoding="utf-8") as output:
                output.write(json.dumps(report, indent=2) + "\n")
    except (ValueError, KeyError, TypeError, AttributeError, OSError, zipfile.BadZipFile,
            RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, "journey=FAIL target=" + args.target + " :: " + str(error) + "\n")
    for step in report["steps"]:
        print("PASS " + step["id"])
    print("journey=PASS target=" + args.target + " edition=" + report["artifact"]["edition"]
          + " scope=offline-core qualification=pending")


if __name__ == "__main__":
    main()
