#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: package_linux_zip.py
# Description: Audit and assemble the Linux preview zip without asserting target qualification.

"""Audit and assemble the Linux preview zip without asserting target qualification."""

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile


# Computes the SHA-256 digest of one input file.
#@param path Path|str Input file or package path under inspection.
#@return str digest Lowercase SHA-256 digest of the input file.
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# Runs the package linux zip command and reports its status.
#@param none No arguments.
#@return None result No value; writes the verified Linux edition ZIP.
def main():
    repo, output, cache = (pathlib.Path(value).resolve() for value in sys.argv[1:])
    artifacts = output / "artifacts"
    package = output / "zip-package"
    docs = package / "docs"
    licenses = docs / "licenses"
    licenses.mkdir(parents=True, exist_ok=True)
    allowed_dependencies = {
        "libc.so.6", "libdl.so.2", "libm.so.6", "libpthread.so.0",
        "librt.so.1", "libgcc_s.so.1",
    }

    shipped = [artifacts / "yaca"]
    inventory = []
    for path in shipped:
        header = subprocess.check_output(
            ["readelf", "-h", str(path)], text=True)
        assert re.search(r"Class:\s+ELF64", header), f"not ELF64: {path}"
        assert re.search(r"Machine:\s+Advanced Micro Devices X86-64", header), path
        dynamic = subprocess.check_output(
            ["readelf", "-d", str(path)], text=True)
        dependencies = re.findall(r"Shared library: \[([^\]]+)\]", dynamic)
        assert set(dependencies) <= allowed_dependencies, (path, dependencies)
        versions = subprocess.check_output(
            ["readelf", "--version-info", str(path)], text=True)
        symbols = re.findall(r"Name: GLIBC_([0-9.]+)", versions)
        # Converts a GLIBC version to numeric components for comparison.
        #@param v str GLIBC version suffix reported by readelf.
        #@return list[int] Numeric version components in comparison order.
        highest = max(symbols, key=lambda v: [int(x) for x in v.split(".")]) \
            if symbols else "0"
        assert [int(x) for x in highest.split(".")] <= [2, 17], \
            f"glibc baseline exceeded in {path}: {highest}"
        (output / "logs" / (path.name + "-elf.txt")).write_text(
            header + dynamic + versions)
        inventory.append({
            "path": str(path.relative_to(output)), "sha256": digest(path),
            "bytes": path.stat().st_size, "dependencies": dependencies,
        })

    shutil.copyfile(repo / "LICENSE", package / "LICENSE")
    shutil.copyfile(repo / "release/LINUX-QUICKSTART.md",
                    docs / "LINUX-QUICKSTART.md")
    notices = {
        "Lua-MIT.html": output / "work/lua-5.5.1/doc/readme.html",
        "Expat-MIT.txt": output / "work/expat-2.8.2/COPYING",
        "LuaExpat-MIT.html": output / "work/luaexpat-1.5.2/docs/license.html",
        "luainstaller-LGPL.txt": output / "work/luainstaller/LICENSE",
        "curl.txt": output / "work/curl-8.21.0/COPYING",
        "Mbed-TLS.txt": output / "work/mbedtls-3.6.7/LICENSE",
    }
    for name, source in notices.items():
        assert source.is_file(), f"missing license: {source}"
        shutil.copyfile(source, licenses / name)
    shutil.copyfile(cache / "cacert-2026-08-13.pem", licenses / "Mozilla-CA.pem")
    (docs / "COMPONENTS.txt").write_text(
        "yaca 0.1.0 preview: GPL-3.0-only\n"
        "luainstaller 1.3.0 launcher/extractor: LGPL-3.0-or-later\n"
        "Lua 5.5.1, LuaExpat 1.5.2, Expat 2.8.2: MIT\n"
        "curl 8.21.0: curl license; Mbed TLS 3.6.7: Apache-2.0\n"
        "Mozilla CA store 2026-08-13: MPL-2.0\n"
        "Built and qualified in a CentOS 7.9.2009 container (glibc 2.17, GCC\n"
        "4.8.5); the container shares the host kernel, so bare-metal CentOS 7\n"
        "power-loss and filesystem qualification remains pending.\n",
        encoding="ascii",
    )
    (package / "README.txt").write_bytes(
        b"yaca 0.1.0 Linux preview (x86_64, CentOS 7 API baseline)\n"
        b"Extract the complete zip to a writable directory, for example\n"
        b"/opt/yaca or ~/yaca, then:\n"
        b"  ./yaca --version\n"
        b"  ./yaca --model-repl\n"
        b"  ./yaca ~/work/project\n"
        b"Use the complete provider request URL, remote model ID and API key.\n"
        b"Data is stored in __yaca__ beside the yaca executable.\n"
        b"Keep that directory on upgrades. See docs/LINUX-QUICKSTART.md.\n"
        b"This is a preview. Bare-metal CentOS 7 qualification is pending.\n"
    )
    (package / "Install.sh").write_bytes(
        b"#!/bin/sh\n"
        b"# Run from your existing shell. No administrator rights required.\n"
        b'PATH="$(dirname "$0"):$PATH"\n'
        b'export PATH\n'
        b'echo "yaca is available in this shell."\n'
    )
    (package / "Install.sh").chmod(0o755)
    (package / "yaca").write_bytes(shipped[0].read_bytes())
    (package / "yaca").chmod(0o755)

    build_summary = output / "build-summary.txt"
    assert build_summary.is_file(), "qualification build summary is missing"
    summary_text = build_summary.read_text()
    assert "status=PASS" in summary_text
    assert "target=linux-x86_64" in summary_text
    assert "full_tests=" in summary_text
    summary = {
        "schema": "yaca-linux-preview-v1", "status": "assembled",
        "target": "linux-x86_64",
        "intended_deployment": "CentOS 7 x86_64 and later glibc baselines",
        "lua": "5.5.1", "build_jobs": 1,
        "qualification_summary": "build-summary.txt",
        "release_authorized": False, "target_qualification_complete": False,
        "runtime_evidence":
            "See build-summary.txt; the qualification ran inside a CentOS "
            "7.9.2009 container sharing the host kernel.",
        "artifacts": inventory,
    }
    (docs / "build-summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    components = [
        ("yaca", "0.1.0-preview", "GPL-3.0-only", output / "yaca-source.tar.gz"
         if (output / "yaca-source.tar.gz").is_file() else shipped[0]),
        ("luainstaller", "1.3.0", "LGPL-3.0-or-later",
         cache / "luainstaller-97192d1.tar.gz"),
        ("Lua", "5.5.1", "MIT", cache / "lua-5.5.1.tar.gz"),
        ("LuaExpat", "1.5.2", "MIT", cache / "luaexpat-1.5.2.tar.gz"),
        ("Expat", "2.8.2", "MIT", cache / "expat-2.8.2.tar.gz"),
        ("curl", "8.21.0", "curl", cache / "curl-8.21.0.tar.xz"),
        ("MbedTLS", "3.6.7", "Apache-2.0", cache / "mbedtls-3.6.7.tar.bz2"),
        ("Mozilla-CA", "2026-08-13", "MPL-2.0", cache / "cacert-2026-08-13.pem"),
    ]
    sbom = {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "yaca Linux preview source components",
        "documentNamespace": "https://github.com/Water-Run/yaca/preview/"
            + digest(package / "yaca"),
        "creationInfo": {"creators": ["Tool: yaca-linux-candidate-builder"],
            "created": "2026-09-19T00:00:00Z"},
        "packages": [{
            "name": name, "SPDXID": "SPDXRef-" + name, "versionInfo": version,
            "downloadLocation": "NOASSERTION", "filesAnalyzed": False,
            "licenseConcluded": license_id, "licenseDeclared": license_id,
            "copyrightText": "NOASSERTION",
            "checksums": [{"algorithm": "SHA256", "checksumValue": digest(path)}],
            "sourceInfo": "Exact source archive in the qualification source "
                "cache; target qualification pending.",
        } for name, version, license_id, path in components],
        "relationships": [{"spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-yaca"}]
            + [{"spdxElementId": "SPDXRef-yaca", "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": "SPDXRef-" + item[0]} for item in components[1:]],
    }
    (docs / "SBOM.spdx.json").write_text(json.dumps(sbom, indent=2) + "\n")

    # The shipped archive pre-creates the empty data root so a first
    # --self-test passes on a clean machine; the program owns all files in it.
    (package / "__yaca__").mkdir(exist_ok=True)
    zip_output = output / "yaca-0.1.0-preview-linux-x86_64.zip"
    with zipfile.ZipFile(zip_output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(package.rglob("*")):
            if path.is_dir() and path.name == "__yaca__":
                info = zipfile.ZipInfo(str(path.relative_to(package)) + "/")
                info.external_attr = (0o755 << 16) | 0x10
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, b"")
            if path.is_file():
                info = zipfile.ZipInfo(str(path.relative_to(package)))
                mode = 0o755 if path.suffix == "" or path.name == "Install.sh" \
                    else 0o644
                info.external_attr = (mode << 16)
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes())
    (output / "SHA256SUMS.txt").write_text(
        f"{digest(zip_output)}  {zip_output.name}\n")
    print("linux zip assembled:", zip_output)


if __name__ == "__main__":
    main()
