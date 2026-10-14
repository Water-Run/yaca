#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-14
# File: prepare_win64_full.py
# Description: Stage the win64 full toolbox with explicit byte-bound Git source profiles and preserved closure status.

"""Stage the win64 full toolbox from std staging, cross builds, and official portable packages.

Arguments: STD_STAGED BUILD_ROOT PYTHON38_ZIP SOURCE_CACHE OUTPUT
           --git-source ARCHIVE --git-source-sha256 SHA256
STD_STAGED is a completed prepare_win64_std.py output. BUILD_ROOT contains
out/jq, out/sqlite, out/busybox, unpack/w64devkit, and the PortableGit tree at
unpack/ itself. Git sources must be a verified matching source profile;
partial closure remains partial. Extraction and compilation are done by the caller.
"""

import argparse
import hashlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tarfile

REPO = pathlib.Path(__file__).resolve().parents[2]
SOURCE_SPEC = importlib.util.spec_from_file_location('yaca_git_source_audit', REPO / '.tools/qualification/audit_corresponding_sources.py')
SOURCE_AUDIT = importlib.util.module_from_spec(SOURCE_SPEC)
SOURCE_SPEC.loader.exec_module(SOURCE_AUDIT)


# Computes a SHA-256 digest for the staged payload.
#@param path Path|str Input file or package path under inspection.
#@return str digest Hexadecimal SHA-256 digest of the supplied data.
#@error Propagates missing-file and read errors.
#@effect Reads the selected input in bounded blocks without changing it.
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
#@param source Path|str Existing program input selected by the staging caller.
#@param destination Path Destination path whose parent already exists.
#@return None No value; copies exactly one file with mode 0755.
#@error Propagates copy and chmod failures.
#@effect Writes destination and sets its portable execute mode.
def copy_program(source, destination):
    shutil.copyfile(source, destination)
    destination.chmod(0o755)


# Recursively copies a tool tree pruning development payload.
#@param source Path|str Source directory to copy.
#@param destination Path|str Destination directory inside the staged tree.
#@param prune set Basenames pruned from the copied tree.
#@return None No value; copies the pruned portable tree.
#@error Propagates copy and filesystem failures.
#@effect Creates or updates destination; existing input files are unchanged.
def copy_tree(source, destination, prune):
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    # Prunes named development and cache payload per tree.
                    #@param directory str Candidate directory name under the copy root.
                    #@param entries list Directory entries within the visited directory.
                    #@return set[str] Entry basenames excluded from the portable copy.
                    ignore=shutil.ignore_patterns(*prune))


# Records every staged file of one tool directory into its payload list.
#@param output Path Staging root.
#@param directory str Tool directory name below tools.
#@return list Payload records with exact destination digests.
#@error Propagates directory traversal and file read failures.
#@effect Reads staged bytes and records archive paths with forward slashes on every build host.
def collect(output, directory):
    payload = []
    for path in sorted((output / "tools" / directory).rglob("*")):
        if path.is_file():
            relative = path.relative_to(output).as_posix()
            payload.append({"source": relative, "destination": relative,
                            "sha256": sha256(path),
                            "executable": path.suffix in (".exe", ".bat", ".cmd")
                                or path.read_bytes()[:2] == b"MZ"})
    return payload


# Stage the Win64 full toolbox with explicitly admitted Git, compiler and Python source profiles.
#@param none Parses five staging paths and required --git-source/--git-source-sha256 options from argv.
#@return None result No value; writes the staged tree and tool-inputs.json.
#@error Raises for rejected source bundles, invalid archives, missing inputs or failed filesystem operations.
#@effect Copies payloads, extracts the selected Python ZIP and runs the maintained source bundler; staged programs do not run.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('std_staged', 'build_root', 'python_zip', 'source_cache', 'output'):
        parser.add_argument(name, type=pathlib.Path)
    parser.add_argument('--git-source', type=pathlib.Path, required=True)
    parser.add_argument('--git-source-sha256', required=True)
    args = parser.parse_args()
    std_staged, root, py38_zip, cache, output = (
        args.std_staged, args.build_root, args.python_zip, args.source_cache, args.output)
    git_source = SOURCE_AUDIT.admit_git_source(args.git_source, args.git_source_sha256, '2.46.2')
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

    import zipfile
    with zipfile.ZipFile(py38_zip) as archive:
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
    subprocess.run([sys.executable, str(REPO / ".tools/qualification/bundle_corresponding_sources.py"),
                    str(REPO / "release/windows-compiler-sources.lock.json"), str(cache),
                    str(sources / "compiler/w64devkit-2.9.0-corresponding-source.tar.gz")], check=True)
    git_archive = sources / "git/git-for-windows-2.46.2-sources.tar.gz"
    shutil.copyfile(git_source['path'], git_archive)
    if sha256(git_archive) != git_source['sha256']:
        raise ValueError('Git source changed during staging')
    python_bundle = sources / "python3/python38-windows-corresponding-source.tar.gz"
    subprocess.run([sys.executable, str(REPO / ".tools/qualification/bundle_corresponding_sources.py"),
                    str(REPO / "release/windows-python38-sources.lock.json"), str(cache),
                    str(python_bundle)], check=True)

    specifications = (
        ("git", "git", "2.46.2", ["cmd/git.exe", "bin/git.exe"],
         "GPL-2.0-only", ["LICENSE.txt"],
         "git/git-for-windows-2.46.2-sources.tar.gz",
         "https://github.com/git-for-windows/git/releases/tag/v2.46.2.windows.1"),
        ("python3", "python3", "3.8.20", ["python.exe"], "Python-2.0.1",
         ["LICENSE.txt"], "python3/python38-windows-corresponding-source.tar.gz",
         "https://www.python.org/downloads/release/python-3820/"),
        ("sqlite", "sqlite", "3.53.4", ["sqlite3.exe", "sqldiff.exe"],
         "Public-Domain-style sqlite blessing", ["LICENSE.md"],
         "sqlite/sqlite-full-source.tar.gz", "https://sqlite.org/download.html"),
        ("jq", "jq", "1.8.2", ["jq.exe"], "MIT", ["COPYING"],
         "jq/jq-onig-source.tar.gz", "https://github.com/jqlang/jq/releases/tag/jq-1.8.2"),
        ("busybox", "busybox", "FRP-6075-g169694ebd", ["busybox.exe"],
         "GPL-2.0-only", ["LICENSE"],
         "busybox/busybox-w32-FRP-6075-g169694ebd.tar.gz",
         "https://github.com/rmyorston/busybox-w32"),
        ("compiler", "compiler", "w64devkit-2.9.0-x64",
         ["bin/gcc.exe", "bin/g++.exe", "bin/ld.exe", "bin/make.exe"],
         "GPL-3.0-or-later WITH GCC-exception-3.1",
         ["COPYING.MinGW-w64-runtime.txt"],
         "compiler/w64devkit-2.9.0-corresponding-source.tar.gz",
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
        if identifier == 'git':
            records[-1]['source_closure'] = git_source['source_closure']
    document = {"schema": "yaca-tool-inputs-v1", "target": "win64-x86_64",
                "tools": records}
    (output / "tool-inputs.json").write_text(json.dumps(document, indent=2) + "\n",
                                             encoding="utf-8")
    print("win64-full-staging=PASS tools=%d target-qualification=pending"
          % len(records))


if __name__ == "__main__":
    main()
