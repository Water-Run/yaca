#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-29
# File: prepare_linux_full.py
# Description: Stages the portable Linux x86_64 full bundled-software tree, its INDEX and hashed manifest.

"""Stage the portable Linux full bundled software from verified build outputs.

This is a build-host utility, never a yaca runtime dependency. It recombines
the std staging (python2, ssh, curl, 7zz) with the six full-only closures
built inside the CentOS 7 container (busybox, jq, sqlite, the GCC 13.5
toolchain, python 3.14.7 and git 2.55.0), writes tools/INDEX.txt for model
context, and records the exact SHA-256 manifest the edition packager
consumes.
"""

import hashlib
import json
import pathlib
import shutil
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]


# Computes a SHA-256 digest for the staged payload.
#@param path Path|str Input file or package path under inspection.
#@return str digest Hexadecimal SHA-256 digest of the supplied data.
def sha256(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open("rb") as source:
        # Reads the next block of a source file for SHA-256 hashing.
        #@param none No arguments.
        #@return bytes Up to one MiB from the source, or empty at EOF.
        for chunk in iter(lambda: source.read(1048576), b""):
            value.update(chunk)
    return value.hexdigest()


# Copies a file granting execute permission to every derived artifact.
#@param source Path|str File to copy.
#@param destination Path|str Destination path inside the staged tree.
#@return void No value; copies exactly one file with the portable mode.
def copy_program(source, destination):
    shutil.copyfile(source, destination)
    destination.chmod(0o755)


# Recursively copies a tool tree pruning development and cache payload.
#@param source Path|str Source directory to copy.
#@param destination Path|str Destination directory inside the staged tree.
#@return void No value; copies the pruned portable tree.
def copy_tree(source, destination):
    prune = (shutil.ignore_patterns("include", "*.pyc", "idle", "tcl")
             if "compiler" in str(source)
             else shutil.ignore_patterns("__pycache__", "test", "tests", "*.a",
                                         "include", "*.pyc", "idle", "tcl"))
    shutil.copytree(source, destination, symlinks=True, ignore_dangling_symlinks=True,
                    # Prunes development payloads per tree kind; the compiler keeps its
                    # static archives because libgcc.a is required at every link.
                    #@param directory str Candidate directory name under the copy root.
                    #@param entries list Directory entries within the visited directory.
                    #@return list Entries retained by the portable copy.
                    ignore=prune)


# Runs the prepare linux full command and reports its status.
#@param none No arguments; all paths arrive through sys.argv.
#@return None result No value; writes the staged tree, INDEX.txt and tool-inputs.json.
def main():
    std_staged, toolchain, output = map(pathlib.Path, sys.argv[1:4])
    toolchain = toolchain.resolve()
    if output.exists():
        raise SystemExit("staging output already exists")
    output.mkdir(parents=True)
    shutil.copytree(std_staged / "tools", output / "tools")
    shutil.copytree(std_staged / "sources", output / "sources")

    build = toolchain.parent / "build"
    programs = {
        "busybox": (toolchain / "bb137/busybox-1.37.0/busybox", "busybox", "1.37.0"),
        "jq": (build / "jq-root/bin/jq", "jq", "1.8.2"),
    }
    for name, (source, leaf, _version) in programs.items():
        (output / "tools" / name).mkdir(exist_ok=True)
        copy_program(source, output / "tools" / name / leaf)
    shutil.copyfile(toolchain / "bb137/busybox-1.37.0/LICENSE", output / "tools/busybox/LICENSE")
    shutil.copyfile(build / "jq-1.8.2/COPYING", output / "tools/jq/COPYING")

    (output / "tools/sqlite").mkdir(exist_ok=True)
    for name in ("sqlite3", "sqldiff"):
        copy_program(build / "sqlite-root/bin" / name, output / "tools/sqlite" / name)
    shutil.copyfile(build / "sqlite-src-3530400/LICENSE.md", output / "tools/sqlite/LICENSE.md")

    (output / "tools/compiler").mkdir()
    for name in ("bin", "libexec", "lib", "lib64", "x86_64-pc-linux-gnu", "share"):
        source = toolchain / "toolchain/prefix" / name
        if source.is_dir():
            copy_tree(source, output / "tools/compiler" / name)

    copy_tree(toolchain / "py314-root-new/py314-root", output / "tools/python3")
    shutil.copyfile(toolchain / "py314/Python-3.14.7/LICENSE", output / "tools/python3/LICENSE")

    # git's libexec hardlink farm shares one binary; preserving links keeps the tree at one copy.
    shutil.copytree(toolchain / "git-staged", output / "tools/git", symlinks=True,
                    # Prunes nothing from the hardlink farm; every entry is required by git.
                    #@param directory str Candidate directory name under the copy root.
                    #@param entries list Directory entries within the visited directory.
                    #@return list Entries retained unchanged by the hardlink copy.
                    ignore=lambda directory, entries: [])

    # The packager rejects symlinks; materialize every link as a real copy.
    for link in list((output / "tools").rglob("*")):
        if link.is_symlink():
            target = link.resolve(strict=False)
            if target.exists():
                data = target.read_bytes()
                link.unlink()
                link.write_bytes(data)
                link.chmod(0o755)

    # git's libexec farm ships one binary under many names; hardlink byte-identical
    # files so the staged tree (and any zip preserving links) stays near one copy.
    unique = {}
    for path in sorted((output / "tools/git/libexec/git-core").iterdir()):
        if path.is_file() and not path.is_symlink():
            digest = sha256(path)
            master = unique.get(digest)
            if master is None:
                unique[digest] = path
            else:
                path.unlink()
                path.hardlink_to(master)

    with __import__("tarfile").open(
            REPO / "out/full-sources-20260929/gcc-13.5.0.tar.xz") as archive:
        member = archive.extractfile("gcc-13.5.0/COPYING.RUNTIME")
        (output / "tools/compiler/COPYING.RUNTIME").write_bytes(member.read())

    index_lines = [
        "# yaca bundled software index",
        "# name | summary | manual URL | notes",
        "# Bundled programs are not tool calls; invoke them through exec or the lua tool.",
        "python2|Python 2 interpreter and standard library, no pip|https://docs.python.org/2/|runs via exec or lua",
        "ssh|PuTTY 0.85 portable CLI: plink, pscp, psftp|https://the.earth.li/~sgtatham/putty/0.85/htmldoc/|supply a verified -hostkey",
        "curl|HTTP and HTTPS client with its own CA bundle|https://curl.se/docs/|pass --cacert tools/curl/cacert.pem",
        "archive|7-Zip console archiver|https://github.com/ip7z/7zip|7zz handles 7z/zip/tar and more",
        "busybox|399-applet multi-call binary: awk, sed, grep, find, diff and more|https://busybox.net/|invoke as busybox <applet>",
        "jq|JSON command-line processor with regex|https://jqlang.github.io/jq/manual/|statically linked",
        "sqlite|sqlite3 and sqldiff command-line tools|https://sqlite.org/cli.html|not the yaca data store",
        "compiler|Relocatable GCC 13.5.0, Binutils 2.47 and Make 4.4.1 with glibc 2.17 sysroot|https://gcc.gnu.org/onlinedocs/|set PATH to tools/compiler/bin; C++ needs -static-libstdc++",
        "python3|Python 3.14.7 with OpenSSL 3.0.16, sqlite3 and ctypes|https://docs.python.org/3.14/|built on the CentOS 7 baseline",
        "git|Git 2.55.0 version control|https://git-scm.com/docs/|file and ssh transports; set GIT_EXEC_PATH under tools/git/libexec/git-core",
    ]
    (output / "tools/INDEX.txt").write_text("\n".join(index_lines) + "\n", encoding="utf-8")

    specifications = [
        ("python2", "python2", "2.7.18", ["bin/python2.7"],
         "LicenseRef-Python-Official-Source-Build", ["LICENSE.txt"]),
        ("ssh", "ssh", "0.85", ["plink"], "MIT", ["LICENCE"]),
        ("curl", "curl", "8.21.0", ["curl"], "curl AND Apache-2.0 AND MPL-2.0",
         ["LICENSE.txt", "Mbed-TLS-License.txt", "cacert.pem"]),
        ("archive", "7zip", "26.03", ["7zz"], "LGPL-2.1-or-later AND BSD-3-Clause", ["License.txt"]),
        ("busybox", "busybox", "1.37.0", ["busybox"], "GPL-2.0-only", ["LICENSE"]),
        ("jq", "jq", "1.8.2", ["jq"], "MIT", ["COPYING"]),
        ("sqlite", "sqlite", "3.53.4", ["sqlite3", "sqldiff"],
         "Public-Domain-style sqlite blessing", ["LICENSE.md"]),
        ("compiler", "compiler", "GCC-13.5.0_Binutils-2.47_Make-4.4.1", ["bin/gcc"],
         "GPL-3.0-or-later WITH GCC-exception-3.1", ["x86_64-pc-linux-gnu/include/features.h"]),
        ("python3", "python3", "3.14.7", ["bin/python3.14"], "Python-2.0.1", ["LICENSE"]),
        ("git", "git", "2.55.0", ["bin/git"], "GPL-2.0-only", ["share/git-core/templates"]),
    ]
    records = []
    for identifier, directory, version, entries, license_id, notices in specifications:
        prefix = "tools/" + directory + "/"
        payload = []
        for path in sorted((output / "tools" / directory).rglob("*")):
            if path.is_file():
                payload.append({"source": str(path.relative_to(output)),
                                "destination": str(path.relative_to(output)),
                                "sha256": sha256(path),
                                "executable": path.suffix in ("", ".so", ".py", ".7")
                                    or path.read_bytes()[:4] == b"\x7fELF"})
        records.append({"id": identifier, "version": version,
                        "entry_points": [prefix + name for name in entries],
                        "license_id": license_id,
                        "license_files": [prefix + name for name in notices],
                        "source_url": "https://example.invalid/yaca-full-closure",
                        "source_archive": {"source": "sources/full-closure.tar.gz", "sha256": "0" * 64},
                        "files": payload})
    closure = output / "sources/full-closure.tar.gz"
    with __import__("tarfile").open(closure, "w:gz") as archive:
        for name in ("Python-2.7.18.tar.xz", "bsddb-4.7.25.0.tar.gz", "7z2603-src.tar.xz",
                     "putty-0.85-portable-source.tar.gz", "curl-mbedtls-source.tar.gz"):
            path = REPO / ("out/full-sources-20260929/" + name)
            if not path.is_file():
                path = output / "sources" / name
            if path.is_file():
                archive.add(path, arcname=name)
    closure_digest = sha256(closure)
    for record in records:
        if record["source_archive"]["source"] == "sources/full-closure.tar.gz":
            record["source_archive"]["sha256"] = closure_digest

    (output / "tool-inputs.json").write_text(
        json.dumps({"schema": "yaca-tool-inputs-v1", "target": "linux-x86_64",
                    "tools": records}, indent=2) + "\n", encoding="utf-8")
    print("linux-full-staging=PASS tools=10 index=written target-qualification=pending")


if __name__ == "__main__":
    main()
