#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-01
# File: prepare_win32_full.py
# Description: Stage the win32 full toolbox from std staging, cross builds, and official portable packages.

"""Stage the win32 full toolbox from std staging, cross builds, and official portable packages.

Arguments: STD_STAGED BUILD_ROOT PYTHON34_ZIP SOURCE_CACHE PAYLOADS OUTPUT
STD_STAGED is a completed prepare_win32_std.py output. BUILD_ROOT contains
out/jq, out/sqlite, out/busybox, unpack/w64devkit, and the PortableGit tree at
unpack/ itself. All extraction and compilation is done by the caller.
"""

import hashlib
import json
import pathlib
import shutil
import sys
import tarfile


REPO = pathlib.Path(__file__).resolve().parents[2]


# Computes a SHA-256 digest for the staged payload.
#@param path Path|str Input file or package path under inspection.
#@return str digest Hexadecimal SHA-256 digest of the supplied data.
def sha256(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open("rb") as source:
        # Reads the next block of a source file for SHA-256 hashing.
        #@param none No arguments.
        #@return bytes Up to one MiB from the source, or empty bytes at EOF.
        for chunk in iter(lambda: source.read(1048576), b""):
            value.update(chunk)
    return value.hexdigest()


# Copies a file granting execute permission to every derived program.
#@param source Path|str File to copy.
#@param destination Path|str Destination path inside the staged tree.
#@return void No value; copies exactly one file with the portable mode.
def copy_program(source, destination):
    shutil.copyfile(source, destination)
    destination.chmod(0o755)


# Recursively copies a tool tree pruning development payload.
#@param source Path|str Source directory to copy.
#@param destination Path|str Destination directory inside the staged tree.
#@param prune set Basenames pruned from the copied tree.
#@return void No value; copies the pruned portable tree.
def copy_tree(source, destination, prune):
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    # Prunes named development and cache payload per tree.
                    #@param directory str Candidate directory name under the copy root.
                    #@param entries list Directory entries within the visited directory.
                    #@return list Entries retained by the portable copy.
                    ignore=shutil.ignore_patterns(*prune))


# Records every staged file of one tool directory into its payload list.
#@param output Path Staging root.
#@param directory str Tool directory name below tools.
#@return list Payload records with exact destination digests.
def collect(output, directory):
    payload = []
    for path in sorted((output / "tools" / directory).rglob("*")):
        if path.is_file():
            relative = str(path.relative_to(output))
            payload.append({"source": relative, "destination": relative,
                            "sha256": sha256(path),
                            "executable": path.suffix in (".exe", ".bat", ".cmd")
                                or path.read_bytes()[:2] == b"MZ"})
    return payload


# Runs the prepare win32 full command and reports its status.
#@param none No arguments; all paths arrive through sys.argv.
#@return None result No value; writes the staged tree and tool-inputs.json.
def main():
    std_staged, root, py34_zip, cache, payloads, output = map(pathlib.Path, sys.argv[1:7])
    root = root.resolve()
    if output.exists():
        raise SystemExit("staging output already exists")
    output.mkdir(parents=True)
    shutil.copytree(std_staged / "tools", output / "tools")
    shutil.copytree(std_staged / "sources", output / "sources")

    for name in ("jq", "sqlite", "busybox"):
        shutil.copytree(root / "out" / name, output / "tools" / name)

    (output / "tools/compiler").mkdir()
    w64 = root / "unpack/w64devkit"
    for name in ("bin", "lib", "libexec", "include"):
        # The lib import archives are linker inputs, not development cruft:
        # pruning them leaves a compiler that cannot link anything.
        copy_tree(w64 / name, output / "tools/compiler" / name,
                  {"__pycache__"})
    for name in ("VERSION.txt", "COPYING.MinGW-w64-runtime.txt", "README.md"):
        shutil.copyfile(w64 / name, output / "tools/compiler" / name)

    copy_tree(root / "unpack", output / "tools/git",
              {"tmp", "w64devkit", "w64devkit-unpack.log", "portablegit-unpack.log"})

    with zipfile_zip(py34_zip) as archive:
        archive.extractall(output / "tools/_py3_tmp")
    shutil.move(str(output / "tools/_py3_tmp/python3"), str(output / "tools/python3"))
    shutil.rmtree(output / "tools/_py3_tmp")

    sources = output / "sources"
    for tool in ("jq", "sqlite", "busybox", "compiler", "git", "python3"):
        (sources / tool).mkdir(parents=True, exist_ok=True)
    jq_bundle = sources / "jq/jq-onig-source.tar.gz"
    with tarfile.open(jq_bundle, "w:gz") as archive:
        for name in ("jq-1.8.2.tar.gz", "onig-6.9.10.tar.gz"):
            archive.add(cache / name, arcname=name)
    sqlite_bundle = sources / "sqlite/sqlite-full-source.tar.gz"
    with tarfile.open(sqlite_bundle, "w:gz") as archive:
        archive.add(cache / "sqlite-autoconf-3530400.tar.gz",
                    arcname="sqlite-autoconf-3530400.tar.gz")
        archive.add(cache / "sqlite-src-3530400.zip", arcname="sqlite-src-3530400.zip")
    shutil.copyfile(cache / "busybox-w32-FRP-6075-g169694ebd.tar.gz",
                    sources / "busybox/busybox-w32-FRP-6075-g169694ebd.tar.gz")
    shutil.copyfile(payloads / "w64devkit-x86-2.9.0.7z.exe",
                    sources / "compiler/w64devkit-x86-2.9.0.7z.exe")
    shutil.copyfile(payloads / "PortableGit-2.10.0-32-bit.7z.exe",
                    sources / "git/PortableGit-2.10.0-32-bit.7z.exe")
    python_bundle = sources / "python3/python34-portable-closure.tar.gz"
    with tarfile.open(python_bundle, "w:gz") as archive:
        archive.add(py34_zip, arcname="python34-portable.zip")

    specifications = (
        ("git", "git", "2.10.0", ["cmd/git.exe", "bin/git.exe"],
         "GPL-2.0-only", ["LICENSE.txt"],
         "git/PortableGit-2.10.0-32-bit.7z.exe",
         "https://github.com/git-for-windows/git/releases/tag/v2.10.0.windows.1"),
        ("python3", "python3", "3.4.10", ["python.exe"], "Python-2.0.1",
         ["LICENSE.txt"], "python3/python34-portable-closure.tar.gz",
         "https://www.python.org/downloads/release/python-3410/"),
        ("sqlite", "sqlite", "3.53.4", ["sqlite3.exe", "sqldiff.exe"],
         "Public-Domain-style sqlite blessing", ["LICENSE.md"],
         "sqlite/sqlite-full-source.tar.gz", "https://sqlite.org/download.html"),
        ("jq", "jq", "1.8.2", ["jq.exe"], "MIT", ["COPYING"],
         "jq/jq-onig-source.tar.gz", "https://github.com/jqlang/jq/releases/tag/jq-1.8.2"),
        ("busybox", "busybox", "FRP-6075-g169694ebd", ["busybox.exe"],
         "GPL-2.0-only", ["LICENSE"],
         "busybox/busybox-w32-FRP-6075-g169694ebd.tar.gz",
         "https://github.com/rmyorston/busybox-w32"),
        ("compiler", "compiler", "w64devkit-2.9.0-x86",
         ["bin/gcc.exe", "bin/g++.exe", "bin/ld.exe", "bin/make.exe"],
         "GPL-3.0-or-later WITH GCC-exception-3.1",
         ["COPYING.MinGW-w64-runtime.txt"],
         "compiler/w64devkit-x86-2.9.0.7z.exe",
         "https://github.com/skeeto/w64devkit/releases/tag/v2.9.0"),
    )
    records = json.loads((std_staged / "tool-inputs.json").read_text())["tools"]
    for identifier, directory, version, entries, license_id, notices, archive_name, url in specifications:
        prefix = "tools/" + directory + "/"
        records.append({"id": identifier, "version": version,
                        "entry_points": [prefix + name for name in entries],
                        "license_id": license_id,
                        "license_files": [prefix + name for name in notices],
                        "source_url": url,
                        "source_archive": {"source": "sources/" + archive_name,
                                           "sha256": sha256(sources / archive_name)},
                        "files": collect(output, directory)})
    document = {"schema": "yaca-tool-inputs-v1", "target": "win32-x86",
                "tools": records}
    (output / "tool-inputs.json").write_text(json.dumps(document, indent=2) + "\n",
                                             encoding="utf-8")
    print("win32-full-staging=PASS tools=%d target-qualification=pending"
          % len(records))


# Opens a zip archive for reading through the zipfile module.
#@param path Path|str Zip archive path to open.
#@return zipfile.ZipFile Archive object the caller must close.
def zipfile_zip(path):
    import zipfile
    return zipfile.ZipFile(path)


if __name__ == "__main__":
    main()
