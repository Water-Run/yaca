#!/usr/bin/env python3
"""Audit and assemble a win64 Windows preview without asserting target qualification."""

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    repo, output, cache = (pathlib.Path(value).resolve() for value in sys.argv[1:])
    package = output / "package"
    docs = package / "docs"
    licenses = docs / "licenses"
    licenses.mkdir(exist_ok=True)
    allowed_dlls = {
        "kernel32.dll", "msvcrt.dll", "advapi32.dll", "ws2_32.dll",
        "bcrypt.dll", "lua55.dll",
    }
    # The Windows 7 SP1 floor makes the 64-bit msvcrt.dll's own secure-CRT
    # surface a bundled import; only genuinely unbundled CRT linkage stays
    # rejected, and the DLL closure check below is the hard guarantee.
    banned = re.compile(r"api-ms-win-crt|ucrtbase", re.I)
    artifacts = [package / "yaca.exe"] + sorted(
        path for path in (output / "onedir").rglob("*") if path.suffix in (".exe", ".dll")
    )
    inventory = []
    for path in artifacts:
        report = subprocess.check_output(
            ["x86_64-w64-mingw32-objdump", "-p", str(path)], text=True
        )
        assert "file format pei-x86-64" in report, f"wrong architecture: {path}"
        assert re.search(r"^MajorSubsystemVersion\s+6$", report, re.M), path
        assert re.search(r"^MinorSubsystemVersion\s+1$", report, re.M), path
        imports = re.findall(r"DLL Name: (\S+)", report)
        assert {name.lower() for name in imports} <= allowed_dlls, (path, imports)
        # Inspect import tables only: export names and debug strings are not imports.
        import_report = report.split("The Export Tables")[0]
        assert not banned.search(import_report), f"unbundled CRT import: {path}"
        (output / "logs" / (path.name + "-imports.txt")).write_text(report)
        inventory.append({
            "path": str(path.relative_to(output)), "sha256": digest(path),
            "bytes": path.stat().st_size, "imports": imports,
        })

    shutil.copyfile(repo / "LICENSE", package / "LICENSE")
    shutil.copyfile(repo / "release/WINDOWS-QUICKSTART.md", docs / "WINDOWS-QUICKSTART.md")
    notices = {
        "Lua-MIT.html": output / "work/lua-5.5.1/doc/readme.html",
        "Expat-MIT.txt": output / "work/expat-2.8.2/COPYING",
        "LuaExpat-MIT.html": output / "work/luaexpat-1.5.2/docs/license.html",
        "luainstaller-LGPL.txt": output / "work/luainstaller/LICENSE",
        "curl.txt": output / "https/work/curl-8.21.0/COPYING",
        "Mbed-TLS.txt": output / "https/work/mbedtls-3.6.7/LICENSE",
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
        "Exact sources and generated relinking sources accompany this zip\n"
        "in yaca-0.1.0-preview-win64-x86_64-source.tar.gz.\n"
        "Cross-built with MinGW; runtime DLLs are bundled inside yaca.exe.\n",
        encoding="ascii",
    )
    (package / "README.txt").write_bytes(
        b"yaca 0.1.0 Windows preview (64-bit, Windows 7 SP1 API baseline)\r\n"
        b"Extract the complete zip to C:\\yaca, then open cmd.exe:\r\n"
        b"  C:\\yaca\\yaca.exe --version\r\n"
        b"  C:\\yaca\\yaca.exe --model-repl\r\n"
        b"  C:\\yaca\\yaca.exe C:\\work\\project\r\n"
        b"Use the complete provider request URL, remote model ID and API key.\r\n"
        b"Data is stored in __yaca__ beside yaca.exe. Keep that directory on upgrades.\r\n"
        b"See docs\\WINDOWS-QUICKSTART.md for setup and verification.\r\n"
        b"This is a preview. Real Windows 7 and later qualification is pending.\r\n"
    )
    # Session-only PATH avoids setx's legacy length limit and persistent registry
    # expansion. Users run this from the CMD window they intend to use.
    (package / "Install.cmd").write_bytes(
        b"@echo off\r\n"
        b"rem Run from your existing CMD window. No administrator rights required.\r\n"
        b'set "PATH=%~dp0;%PATH%"\r\n'
        b"echo yaca is available in this CMD window.\r\n"
        b"exit /b 0\r\n"
    )
    summary = {
        "schema": "yaca-windows-preview-v1", "status": "cross-build-passed",
        "target": "win64-x86_64", "intended_deployment": "Windows 7 SP1 through Windows 11",
        "image_subsystem": "6.1", "lua": "5.5.1", "build_jobs": 1,
        "base_revision": (output / "logs/base-revision.txt").read_text().strip(),
        "source_snapshot_sha256": digest(output / "yaca-source.tar.gz"),
        "compiler": subprocess.check_output(
            ["x86_64-w64-mingw32-gcc", "--version"], text=True
        ).splitlines()[0],
        "release_authorized": False, "target_qualification_complete": False,
        "runtime_evidence": "See separately recorded smoke results; real targets pending.",
        "artifacts": inventory,
    }
    (docs / "build-summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    components = [
        ("yaca", "0.1.0-preview", "GPL-3.0-only", output / "yaca-source.tar.gz"),
        ("luainstaller", "1.3.0", "LGPL-3.0-or-later", cache / "luainstaller-97192d1.tar.gz"),
        ("Lua", "5.5.1", "MIT", cache / "lua-5.5.1.tar.gz"),
        ("LuaExpat", "1.5.2", "MIT", cache / "luaexpat-1.5.2.tar.gz"),
        ("Expat", "2.8.2", "MIT", cache / "expat-2.8.2.tar.gz"),
        ("curl", "8.21.0", "curl", cache / "curl-8.21.0.tar.xz"),
        ("MbedTLS", "3.6.7", "Apache-2.0", cache / "mbedtls-3.6.7.tar.bz2"),
        ("Mozilla-CA", "2026-08-13", "MPL-2.0", cache / "cacert-2026-08-13.pem"),
    ]
    sbom = {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT", "name": "yaca Windows preview source components",
        "documentNamespace": "https://github.com/Water-Run/yaca/preview/"
            + digest(package / "yaca.exe"),
        "creationInfo": {"creators": ["Tool: yaca-windows-candidate-builder"],
            "created": "2026-09-14T00:00:00Z"},
        "packages": [{
            "name": name, "SPDXID": "SPDXRef-" + name, "versionInfo": version,
            "downloadLocation": "NOASSERTION", "filesAnalyzed": False,
            "licenseConcluded": license_id, "licenseDeclared": license_id,
            "copyrightText": "NOASSERTION",
            "checksums": [{"algorithm": "SHA256", "checksumValue": digest(path)}],
            "sourceInfo": "Exact source archive included in the accompanying source package; "
                "downstream build adjustments are included. Target qualification pending.",
        } for name, version, license_id, path in components],
        "relationships": [{"spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-yaca"}]
            + [{"spdxElementId": "SPDXRef-yaca", "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": "SPDXRef-" + item[0]} for item in components[1:]],
    }
    (docs / "SBOM.spdx.json").write_text(json.dumps(sbom, indent=2) + "\n")

    source_output = output / "yaca-0.1.0-preview-win64-x86_64-source.tar.gz"
    with tarfile.open(source_output, "w:gz") as archive:
        archive.add(output / "yaca-source.tar.gz", arcname="yaca-source.tar.gz")
        archive.add(output / "generated", arcname="generated")
        # Include the actual adjusted generator as well as its locked original.
        archive.add(output / "work/luainstaller", arcname="luainstaller-build-source")
        for name in (
            "lua-5.5.1.tar.gz", "luaexpat-1.5.2.tar.gz", "expat-2.8.2.tar.gz",
            "curl-8.21.0.tar.xz", "mbedtls-3.6.7.tar.bz2",
            "luainstaller-97192d1.tar.gz", "cacert-2026-08-13.pem",
        ):
            archive.add(cache / name, arcname="dependencies/" + name)
    zip_output = output / "yaca-0.1.0-preview-win64-x86_64.zip"
    with zipfile.ZipFile(zip_output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                archive.write(path, str(path.relative_to(package)))
    (output / "SHA256SUMS.txt").write_text(
        "".join(f"{digest(path)}  {path.name}\n" for path in (zip_output, source_output))
    )


if __name__ == "__main__":
    main()
