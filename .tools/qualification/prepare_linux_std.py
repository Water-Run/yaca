#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-29
# File: prepare_linux_std.py
# Description: Stages the portable Linux x86_64 std tool tree and its hashed input manifest.

"""Stage the portable Linux std tools from explicit, verified build inputs.

This is a build-host utility, never a yaca runtime dependency. It recombines the
CentOS 7 built Python 2.7.18 tree, the native PuTTY CLI build, the CentOS-built
curl artifacts and the 7-Zip console executable into the portable layout the
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


# Runs the prepare linux std command and reports its status.
#@param none No arguments; all paths arrive through sys.argv.
#@return None result No value; writes the staged tree and tool-inputs.json.
def main():
    cache, build, core, output = map(pathlib.Path, sys.argv[1:5])
    if output.exists():
        raise SystemExit("staging output already exists")
    output.mkdir(parents=True)
    (output / "tools").mkdir()

    shutil.copytree(build / "python-root/yaca/tools/python2", output / "tools/python2",
                    # Skips development headers and static libraries from the runtime tree.
                    #@param directory str Candidate directory name under the copy root.
                    #@param entries list Directory entries within the visited directory.
                    #@return list Entries retained by the portable runtime copy.
                    ignore=shutil.ignore_patterns("include", "*.a", "python2.7-config",
                                                  "python2-config", "python-config", "idle",
                                                  "smtpd.py", "2to3"))

    shutil.copyfile(build / "Python-2.7.18/LICENSE", output / "tools/python2/LICENSE.txt")

    (output / "tools/ssh").mkdir()
    for name in ("plink", "pscp", "psftp"):
        shutil.copyfile(build / "putty-build" / name, output / "tools/ssh" / name)
    shutil.copyfile(build / "putty-0.85/LICENCE", output / "tools/ssh/LICENCE")
    shutil.copyfile(REPO / "release/patches/putty-0.85-portable.patch", output / "tools/ssh/portable.patch")
    (output / "tools/ssh/README.txt").write_text(
        "PuTTY 0.85 portable CLI build (Linux x86_64, CentOS 7 baseline). Persistent random seed\n"
        "files are disabled; the tools seed from system entropy. Host keys are never saved:\n"
        "supply a verified -hostkey value.\n"
        "Example: ./plink -ssh -batch -noagent -hostkey <verified-fingerprint> user@host command\n"
        "No GUI, Pageant or installer is included.\n", encoding="ascii")

    (output / "tools/curl").mkdir()
    shutil.copyfile(core / "curl", output / "tools/curl/curl")
    shutil.copyfile(core / "cacert.pem", output / "tools/curl/cacert.pem")
    shutil.copyfile(core / "COPYING", output / "tools/curl/LICENSE.txt")
    shutil.copyfile(core / "LICENSE", output / "tools/curl/Mbed-TLS-License.txt")

    (output / "tools/7zip").mkdir()
    shutil.copyfile(build / "CPP/7zip/Bundles/Alone2/_o/7zz", output / "tools/7zip/7zz")
    shutil.copyfile(build / "DOC/License.txt", output / "tools/7zip/License.txt")

    sources = output / "sources"
    sources.mkdir()
    with tarfile.open(sources / "Python-2.7.18-linux-source.tar.gz", "w:gz") as archive:
        for name in ("Python-2.7.18.tar.xz", "bsddb-4.7.25.0.tar.gz"):
            archive.add(cache / name, arcname=name)
        for name in ("prepare_linux_std.py",):
            archive.add(REPO / ".tools/qualification" / name, arcname=name)
        archive.add(REPO / "release/tool-sources.lock.json", arcname="tool-sources.lock.json")
    shutil.copyfile(cache / "7z2603-src.tar.xz", sources / "7z2603-src.tar.xz")
    with tarfile.open(sources / "curl-mbedtls-source.tar.gz", "w:gz") as archive:
        for name in ("curl-8.21.0.tar.xz", "mbedtls-3.6.7.tar.bz2"):
            archive.add(cache / name, arcname=name)
    with tarfile.open(sources / "putty-0.85-portable-source.tar.gz", "w:gz") as archive:
        archive.add(build / "putty-0.85", arcname="putty-0.85",
                    # Omits editor droppings from the bundled putty source tree.
                    #@param item TarInfo Candidate source archive entry.
                    #@return TarInfo|None Original entry, or None for an editor artifact.
                    filter=lambda item: None if item.name.endswith(".orig") else item)
        archive.add(REPO / ".tools/qualification/prepare_linux_std.py", arcname="prepare_linux_std.py")
    records = []
    for identifier, directory_name, version, entries, license_id, notices, source_name, url in (
        ("python2", "python2", "2.7.18", ["bin/python2.7"], "LicenseRef-Python-Official-Source-Build",
         ["LICENSE.txt"], "Python-2.7.18-linux-source.tar.gz", "https://www.python.org/downloads/release/python-2718/"),
        ("ssh", "ssh", "0.85", ["plink", "pscp", "psftp"], "MIT", ["LICENCE"],
         "putty-0.85-portable-source.tar.gz", "https://the.earth.li/~sgtatham/putty/0.85/putty-0.85.tar.gz"),
        ("curl", "curl", "8.21.0", ["curl"], "curl AND Apache-2.0 AND MPL-2.0",
         ["LICENSE.txt", "Mbed-TLS-License.txt", "cacert.pem"], "curl-mbedtls-source.tar.gz", "https://curl.se/download/curl-8.21.0.tar.xz"),
        ("archive", "7zip", "26.03", ["7zz"], "LGPL-2.1-or-later AND BSD-3-Clause",
         ["License.txt"], "7z2603-src.tar.xz", "https://github.com/ip7z/7zip/releases/tag/26.03"),
    ):
        prefix = "tools/" + directory_name + "/"
        payload = [{"source": str(path.relative_to(output)), "destination": str(path.relative_to(output)),
                    "sha256": sha256(path), "executable": path.suffix in ("", ".so", ".7")}
                   for path in sorted((output / "tools" / directory_name).rglob("*")) if path.is_file()]
        source = sources / source_name if source_name else None
        records.append({"id": identifier, "version": version, "entry_points": [prefix + name for name in entries],
                        "license_id": license_id, "license_files": [prefix + name for name in notices],
                        "source_url": url, "source_archive": {"source": "sources/" + source_name, "sha256": sha256(source)},
                        "files": payload})
    (output / "tool-inputs.json").write_text(json.dumps({"schema": "yaca-tool-inputs-v1", "target": "linux-x86_64",
                                                        "tools": records}, indent=2) + "\n", encoding="utf-8")
    print("linux-std-staging=PASS tools=4 target-qualification=pending")


if __name__ == "__main__":
    main()
