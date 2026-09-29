#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-29
# File: prepare_win64_std.py
# Description: Stages the portable Windows x64 std tool tree and its hashed input manifest.

"""Stage the portable Windows x64 std tools from explicit, verified build inputs.

This is a build-host utility, never a yaca runtime dependency. It recombines the
amd64 Python 2.7.18 MSI payload, the x64 PuTTY CLI build, the x64 core curl
artifacts and the 7-Zip x64 console executable into the portable layout the
edition packager consumes, and records the exact SHA-256 manifest for it.
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
        #@return bytes Up to one MiB from the source, or empty at EOF.
        for chunk in iter(lambda: source.read(1048576), b""):
            value.update(chunk)
    return value.hexdigest()


# Extracts a safe basename from an archive member path.
#@param value object Candidate value under validation.
#@return str name Safe final path component of the archive member.
def leaf(value):
    value = value.split("|")[-1]
    if value in ("", ".", "..") or any(char in value for char in "/\\:\0"):
        raise ValueError("unsafe MSI filename")
    return value


# Runs the prepare win64 std command and reports its status.
#@param none No arguments.
#@return None result No value; writes the staged tree and tool-inputs.json.
def main():
    cache, build, core, inventory, output = map(pathlib.Path, sys.argv[1:6])
    if output.exists():
        raise SystemExit("staging output already exists")
    output.mkdir(parents=True)
    (output / "tools").mkdir()

    directories, components, files = {}, {}, []
    # Parses one inventory row into the directory, component or file table.
    #@param row str Tab-separated MSI inventory row.
    #@return void No value; mutates the parsed tables.
    def parse(row):
        columns = row.rstrip("\n").split("\t")
        kind, name, second = columns[0], columns[1], columns[2]
        third = columns[3] if len(columns) > 3 else ""
        if kind == "Directory":
            directories[name] = (second, third)
        elif kind == "Component":
            components[name] = second
        elif kind == "File":
            files.append((name, second, third))
        else:
            raise ValueError("unknown MSI metadata row")

    # Resolves one MSI directory name to its staging-relative path.
    #@param name str Selected fixture, component, or tool name.
    #@param ancestors object The ancestors supplied to this proof operation.
    #@return Path|None path Safe staging directory, or None for an unsafe archive member.
    def directory(name, ancestors=()):
        if name == "TARGETDIR":
            return pathlib.Path(".")
        if name not in directories:
            return None
        if name in ancestors:
            raise ValueError("MSI directory cycle")
        parent, value = directories[name]
        prefix = directory(parent, ancestors + (name,))
        if prefix is None:
            return None
        value = value.split(":")[0]
        return prefix if value == "." else prefix / leaf(value)

    inventory_text = inventory.read_text(encoding="utf-8")
    for row in inventory_text.splitlines():
        if row.startswith(("Directory\t", "Component\t", "File\t")):
            parse(row)

    python = output / "tools/python2"
    python.mkdir(parents=True)
    crt_names = {"msvcr90.dll", "msvcp90.dll", "msvcm90.dll"}
    root_names = crt_names | {"python.exe", "python27.dll", "Microsoft.VC90.CRT.manifest",
                              "LICENSE.txt", "README.txt"}
    for identifier, component, filename in files:
        relative_root = directory(components[component])
        filename = leaf(filename)
        if relative_root is None and filename not in crt_names:
            continue
        relative = pathlib.Path(filename) if filename in crt_names else relative_root / filename
        if relative.parts[0] not in ("Lib", "DLLs", "tcl") and str(relative) not in root_names:
            continue
        source = build / "python-cab" / leaf(identifier)
        destination = python / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and sha256(destination) != sha256(source):
            raise ValueError("conflicting MSI payload: " + str(relative))
        shutil.copyfile(source, destination)
    for name in root_names - {"w9xpopen.exe"}:
        if not (python / name).is_file():
            raise ValueError("portable Python closure is missing " + name)

    for name in ("ssh", "curl", "7zip"):
        (output / "tools" / name).mkdir()
    for name in ("plink", "pscp", "psftp"):
        shutil.copyfile(build / "putty-build" / (name + ".exe"), output / "tools/ssh" / (name + ".exe"))
    shutil.copyfile(build / "putty-0.85/LICENCE", output / "tools/ssh/LICENCE")
    shutil.copyfile(REPO / "release/patches/putty-0.85-portable.patch", output / "tools/ssh/portable.patch")
    (output / "tools/ssh/README.txt").write_text(
        "PuTTY 0.85 portable CLI build (x64). Registry settings and persistent random seed files are disabled.\n"
        "The process seeds from Windows entropy. Host keys are never saved: supply a verified -hostkey value.\n"
        "Example: plink.exe -ssh -batch -noagent -noshare -hostkey <verified-fingerprint> user@host command\n"
        "No -load sessions, GUI, Pageant, jump-list changes, or installer are included.\n", encoding="ascii")
    shutil.copyfile(core / "https/artifacts/curl.exe", output / "tools/curl/curl.exe")
    shutil.copyfile(core / "onedir/.luai/components/cacert.pem", output / "tools/curl/cacert.pem")
    shutil.copyfile(core / "https/work/curl-8.21.0/COPYING", output / "tools/curl/LICENSE.txt")
    shutil.copyfile(core / "https/work/mbedtls-3.6.7/LICENSE", output / "tools/curl/Mbed-TLS-License.txt")
    shutil.copyfile(build / "7zip/x64/7za.exe", output / "tools/7zip/7za.exe")
    for name in ("License.txt", "readme.txt"):
        shutil.copyfile(build / "7zip" / name, output / "tools/7zip" / name)

    sources = output / "sources"
    sources.mkdir()
    with tarfile.open(sources / "Python-2.7.18-amd64-portable-source.tar.gz", "w:gz") as archive:
        for name in ("Python-2.7.18.tar.xz", "bsddb-4.7.25.0.tar.gz"):
            archive.add(cache / name, arcname=name)
        for name in ("msi_inventory.c", "prepare_win64_std.py", "build_win64_std.sh"):
            archive.add(REPO / ".tools/qualification" / name, arcname=name)
        archive.add(REPO / "release/tool-sources.lock.json", arcname="tool-sources.lock.json")
    shutil.copyfile(cache / "7z2603-src.tar.xz", sources / "7z2603-src.tar.xz")
    with tarfile.open(sources / "putty-0.85-portable-source.tar.gz", "w:gz") as archive:
        archive.add(build / "putty-0.85", arcname="putty-0.85")
        for name in ("build_win64_std.sh", "prepare_win64_std.py"):
            archive.add(REPO / ".tools/qualification" / name, arcname=name)
    with tarfile.open(sources / "curl-mbedtls-source.tar.gz", "w:gz") as archive:
        for name in ("curl-8.21.0", "mbedtls-3.6.7"):
            archive.add(core / "https/work" / name, arcname=name,
                        # Omits compiler outputs from the bundled curl and mbedTLS sources.
                        #@param item TarInfo Candidate source archive entry.
                        #@return TarInfo|None Original entry, or None for a build output.
                        filter=lambda item: None if item.name.endswith((".o", ".a", ".lo", ".exe")) else item)

    records = []
    for identifier, directory_name, version, entries, license_id, notices, source_name, url in (
        ("python2", "python2", "2.7.18", ["python.exe"], "LicenseRef-Python-Official-Windows-Bundle",
         ["LICENSE.txt"], "Python-2.7.18-amd64-portable-source.tar.gz", "https://www.python.org/downloads/release/python-2718/"),
        ("ssh", "ssh", "0.85", ["plink.exe", "pscp.exe", "psftp.exe"], "MIT", ["LICENCE"],
         "putty-0.85-portable-source.tar.gz", "https://the.earth.li/~sgtatham/putty/0.85/putty-0.85.tar.gz"),
        ("curl", "curl", "8.21.0", ["curl.exe"], "curl AND Apache-2.0 AND MPL-2.0",
         ["LICENSE.txt", "Mbed-TLS-License.txt", "cacert.pem"], "curl-mbedtls-source.tar.gz", "https://curl.se/download/curl-8.21.0.tar.xz"),
        ("archive", "7zip", "26.03", ["7za.exe"], "LGPL-2.1-or-later AND BSD-3-Clause",
         ["License.txt"], "7z2603-src.tar.xz", "https://github.com/ip7z/7zip/releases/tag/26.03"),
    ):
        prefix = "tools/" + directory_name + "/"
        payload = [{"source": str(path.relative_to(output)), "destination": str(path.relative_to(output)),
                    "sha256": sha256(path), "executable": path.suffix.lower() in (".exe", ".dll", ".pyd")}
                   for path in sorted((output / "tools" / directory_name).rglob("*")) if path.is_file()]
        source = sources / source_name
        records.append({"id": identifier, "version": version, "entry_points": [prefix + name for name in entries],
                        "license_id": license_id, "license_files": [prefix + name for name in notices],
                        "source_url": url, "source_archive": {"source": "sources/" + source_name, "sha256": sha256(source)},
                        "files": payload})
    (output / "tool-inputs.json").write_text(json.dumps({"schema": "yaca-tool-inputs-v1", "target": "win64-x86_64",
                                                        "tools": records}, indent=2) + "\n", encoding="utf-8")
    print("win64-std-staging=PASS tools=4 target-qualification=pending")


if __name__ == "__main__":
    main()
