#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: prepare_win32_std.py
# Description: Stage the Windows std toolbox from pinned sources and read-only MSI metadata.

"""Stage the Windows std toolbox from pinned sources and read-only MSI metadata.

Arguments: SOURCE_CACHE BUILD_DIRECTORY CORE_BUILD MSI_INVENTORY_TSV OUTPUT
BUILD_DIRECTORY contains python-cab, 7zip, putty-0.85, and putty-build.
All extraction and compilation is done by build_win32_std.sh.
"""

import hashlib
import json
import pathlib
import shutil
import sys
import tarfile


REPO = pathlib.Path(__file__).resolve().parents[2]


# Computes a SHA-256 digest for the proof payload.
#@param path Path|str Input file or package path under inspection.
#@return str digest Hexadecimal SHA-256 digest of the supplied data.
def sha256(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open("rb") as source:
        # Reads the next block of a source file for SHA-256 hashing.
        #@param none No arguments.
        #@return bytes Up to one MiB from source, or empty bytes at EOF.
        for chunk in iter(lambda: source.read(1048576), b""):
            value.update(chunk)
    return value.hexdigest()


# Extracts a safe basename from an archive member path.
#@param value object Candidate value under validation.
#@return str name Safe final path component of an archive member.
def leaf(value):
    value = value.split("|")[-1]
    if value in ("", ".", "..") or any(char in value for char in "/\\:\0"):
        raise ValueError("unsafe MSI filename")
    return value


# Runs the prepare win32 std command and reports its status.
#@param none No arguments.
#@return None result No value; stages verified Win32 std tools or raises on invalid inputs.
def main():
    cache, build, core, inventory, output = [pathlib.Path(value).resolve() for value in sys.argv[1:]]
    output.mkdir()
    directories, components, files = {}, {}, []
    for line in inventory.read_text(encoding="utf-8").splitlines():
        kind, name, second, third = line.split("\t")
        if kind == "Directory":
            directories[name] = (second, third)
        elif kind == "Component":
            components[name] = second
        elif kind == "File":
            files.append((name, second, third))
        else:
            raise ValueError("unknown MSI metadata row")

    # Creates a required destination directory under the staging root.
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

    python = output / "tools/python2"
    python.mkdir(parents=True)
    crt_names = {"msvcr90.dll", "msvcp90.dll", "msvcm90.dll"}
    root_names = crt_names | {"python.exe", "python27.dll", "Microsoft.VC90.CRT.manifest",
                              "LICENSE.txt", "README.txt", "w9xpopen.exe"}
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
    for name in root_names:
        if not (python / name).is_file():
            raise ValueError("portable Python closure is missing " + name)

    for name in ("ssh", "curl", "7zip"):
        (output / "tools" / name).mkdir()
    for name in ("plink", "pscp", "psftp"):
        shutil.copyfile(build / "putty-build" / (name + ".exe"), output / "tools/ssh" / (name + ".exe"))
    shutil.copyfile(build / "putty-0.85/LICENCE", output / "tools/ssh/LICENCE")
    shutil.copyfile(REPO / "release/patches/putty-0.85-portable.patch", output / "tools/ssh/portable.patch")
    (output / "tools/ssh/README.txt").write_text(
        "PuTTY 0.85 portable CLI build. Registry settings and persistent random seed files are disabled.\n"
        "The process seeds from Windows entropy. Host keys are never saved: supply a verified -hostkey value.\n"
        "Example: plink.exe -ssh -batch -noagent -noshare -hostkey <verified-fingerprint> user@host command\n"
        "No -load sessions, GUI, Pageant, jump-list changes, or installer are included.\n", encoding="ascii")
    shutil.copyfile(core / "https/artifacts/curl.exe", output / "tools/curl/curl.exe")
    shutil.copyfile(core / "onedir/.luai/components/cacert.pem", output / "tools/curl/cacert.pem")
    shutil.copyfile(core / "https/work/curl-8.21.0/COPYING", output / "tools/curl/LICENSE.txt")
    shutil.copyfile(core / "https/work/mbedtls-3.6.7/LICENSE", output / "tools/curl/Mbed-TLS-LICENSE.txt")
    for name in ("7za.exe", "License.txt", "readme.txt"):
        shutil.copyfile(build / "7zip" / name, output / "tools/7zip" / name)

    sources = output / "sources"
    sources.mkdir()
    with tarfile.open(sources / "Python-2.7.18-portable-source.tar.gz", "w:gz") as archive:
        for name in ("Python-2.7.18.tar.xz", "bsddb-4.7.25.0.tar.gz"):
            archive.add(cache / name, arcname=name)
        for name in ("msi_inventory.c", "prepare_win32_std.py", "build_win32_std.sh"):
            archive.add(REPO / ".tools/qualification" / name, arcname=name)
        archive.add(REPO / "release/tool-sources.lock.json", arcname="tool-sources.lock.json")
    shutil.copyfile(cache / "7z2603-src.tar.xz", sources / "7z2603-src.tar.xz")
    with tarfile.open(sources / "putty-0.85-portable-source.tar.gz", "w:gz") as archive:
        archive.add(build / "putty-0.85", arcname="putty-0.85")
        for name in ("build_win32_std.sh", "prepare_win32_std.py"):
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
         ["LICENSE.txt"], "Python-2.7.18-portable-source.tar.gz", "https://www.python.org/downloads/release/python-2718/"),
        ("ssh", "ssh", "0.85", ["plink.exe", "pscp.exe", "psftp.exe"], "MIT", ["LICENCE"],
         "putty-0.85-portable-source.tar.gz", "https://the.earth.li/~sgtatham/putty/0.85/putty-0.85.tar.gz"),
        ("curl", "curl", "8.21.0", ["curl.exe"], "curl AND Apache-2.0 AND MPL-2.0",
         ["LICENSE.txt", "Mbed-TLS-LICENSE.txt", "cacert.pem"], "curl-mbedtls-source.tar.gz", "https://curl.se/download/curl-8.21.0.tar.xz"),
        ("archive", "7zip", "26.03", ["7za.exe"], "LGPL-2.1-or-later AND BSD-3-Clause",
         ["License.txt"], "7z2603-src.tar.xz", "https://github.com/ip7z/7zip/releases/tag/26.03"),
    ):
        prefix = "tools/" + directory_name + "/"
        payload = [{"source": str(path.relative_to(output)), "destination": str(path.relative_to(output)),
                    # Cygwin unzip maps POSIX modes onto NTFS ACLs. Native
                    # libraries need execute permission too, including .pyd.
                    "sha256": sha256(path), "executable": path.suffix.lower() in (".exe", ".dll", ".pyd")}
                   for path in sorted((output / "tools" / directory_name).rglob("*")) if path.is_file()]
        source = sources / source_name
        records.append({"id": identifier, "version": version, "entry_points": [prefix + name for name in entries],
                        "license_id": license_id, "license_files": [prefix + name for name in notices],
                        "source_url": url, "source_archive": {"source": "sources/" + source_name, "sha256": sha256(source)},
                        "files": payload})
    (output / "tool-inputs.json").write_text(json.dumps({"schema": "yaca-tool-inputs-v1", "target": "win32-x86",
                                                        "tools": records}, indent=2) + "\n", encoding="utf-8")
    print("win32-std-staging=PASS tools=4 target-qualification=pending")


if __name__ == "__main__":
    main()
