#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-02
# File: fetch_v142_toolchain_windows.py
# Description: Fetch and privately extract the pinned MSVC v142 toolchain and Windows 10 SDK for the win64 full Python build.

"""Privately fetch and extract MSVC 14.29 (v142) plus the Windows 10 SDK 19041.

The win64 full edition needs a Windows Python 3.8.20 source build, and the
Windows 7 SP1 target requires the last Win7-compatible CRT generation, so the
compiler must be MSVC 14.29 (v142). This host has no admin rights and no VS2019,
so the toolchain is assembled by direct extraction, following the private SDK
route already used for Python 3.4.10 in build_python34_windows.py:

1. Download the VS2019 release channel manifest and verify its SHA-256 against
   the pinned constant below; the manifest itself is the trust anchor and every
   payload digest is taken from it (Microsoft-published SHA-256 per payload).
2. Resolve the BuildTools product manifest from the channel, again digest
   pinned.
3. Download the selected VC packages (compiler HostX64/TargetX64, CRT headers,
   x64 desktop libs, x64 redist DLLs, props) and every Win10SDK_10.0.19041
   payload (feature MSIs plus their external cabs).
4. Unzip the VC vsix payloads and administratively install (msiexec /a, no
   elevation, no registration) the SDK features a CPython build needs.
5. Emit a manifest of digests for the review record.

Arguments: CACHE_DIR
CACHE_DIR receives downloads/, vc/ and sdk/. Re-running resumes: payloads whose
digest already matches are not fetched again.
"""

import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.request
import zipfile

CHANNEL_URL = "https://aka.ms/vs/16/release/channel"
CHANNEL_SHA256 = "ce478cd78cce92c5c8bdcf4bd5cb17f90ec7be245a772a030563cc7aa096c4c6"
PRODUCT_ID = "Microsoft.VisualStudio.Manifests.VisualStudio"
PRODUCT_SHA256 = "fb642c3f891b70947e0152275e1722ffb3cca7e8700eea0f0fa0f3a7645584cc"
SDK_ID = "Win10SDK_10.0.19041"
VC_IDS = (
    "Microsoft.VC.14.29.16.11.Tools.HostX64.TargetX64.base",
    "Microsoft.VC.14.29.16.11.Tools.HostX64.TargetX64.Res.base",
    "Microsoft.VC.14.29.16.11.CRT.Headers.base",
    "Microsoft.VC.14.29.16.11.CRT.x64.Desktop.base",
    "Microsoft.VC.14.29.16.11.CRT.x64.OneCore.Desktop.base",
    "Microsoft.VC.14.29.16.11.CRT.Redist.X64.base",
    "Microsoft.VC.14.29.16.11.Props.x64",
)
BUILDTOOLS_ID = "Microsoft.Windows.SDK.BuildTools_10.0.19041.8"
SDK_MSIS = (
    "Windows SDK Desktop Headers x64-x86_en-us.msi",
    "Windows SDK Desktop Headers x86-x86_en-us.msi",
    "Windows SDK Desktop Libs x64-x86_en-us.msi",
    "Windows SDK Desktop Libs x86-x86_en-us.msi",
    "Windows SDK for Windows Store Apps Libs-x86_en-us.msi",
    "Windows SDK for Windows Store Apps Headers-x86_en-us.msi",
    "Windows SDK Desktop Tools x64-x86_en-us.msi",
    "Windows SDK Desktop Tools x86-x86_en-us.msi",
    "Windows SDK Signing Tools-x86_en-us.msi",
    "Windows SDK Modern Versioned Developer Tools-x86_en-us.msi",
    "Windows SDK Modern Non-Versioned Developer Tools-x86_en-us.msi",
    "Universal CRT Headers Libraries and Sources-x86_en-us.msi",
    "Universal CRT Redistributable-x86_en-us.msi",
)


# Computes the SHA-256 digest of one file.
#@param path pathlib.Path File to hash in one-megabyte blocks.
#@return str Hexadecimal SHA-256 digest of the file bytes.
def file_sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        # Reads the next block of the file for SHA-256 hashing.
        #@param none No arguments; closes over the open stream.
        #@return bytes Up to one MiB from the stream, or empty bytes at EOF.
        for chunk in iter(lambda: stream.read(1048576), b""):
            value.update(chunk)
    return value.hexdigest()


# Fetches a URL over TLS and returns its bytes, retrying transient drops.
#@param url str Absolute https URL to download into memory.
#@return bytes Complete response body.
#@error Exits after five consecutive failed attempts with the last error.
def fetch_bytes(url):
    last_error = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=300) as response:
                return response.read()
        except (OSError, urllib.error.URLError) as error:
            last_error = error
            print("retry %d for %s after %s" % (attempt + 1, url, error))
            time.sleep(3 * (attempt + 1))
    raise SystemExit("download failed after retries: %s (%s)" % (url, last_error))


# Downloads one payload unless a digest-matching file already exists.
#@param url str Payload URL supplied by the verified product manifest.
#@param name str File name used for cache storage.
#@param expected str Manifest-published lowercase SHA-256 of the payload.
#@param downloads pathlib.Path Directory receiving the payload file.
#@return pathlib.Path Path of the verified payload in downloads.
#@effect Writes the payload file under downloads when not yet cached.
def download_verified(url, name, expected, downloads):
    target = downloads / name
    if target.exists() and file_sha256(target) == expected.lower():
        return target
    data = fetch_bytes(url)
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected.lower():
        raise SystemExit("digest mismatch for %s: manifest=%s actual=%s"
                         % (name, expected, actual))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    print("fetched %s (%d bytes)" % (name, len(data)))
    return target


# Extracts every vsix payload of the VC toolset into the merged vc tree.
#@param payload_paths list[pathlib.Path] Verified vsix files to unpack.
#@param vc_root pathlib.Path Destination tree for the merged toolset layout.
#@return None result No value; leaves bin/include/lib layout under vc_root.
#@effect Creates and populates vc_root with the overlaid toolset files once;
#@effect later runs skip extraction when the compiler marker already exists.
def extract_vc(payload_paths, vc_root):
    if (vc_root / "Contents/VC/Tools/MSVC/14.29.30133/bin/Hostx64/x64/cl.exe").is_file():
        print("vc extraction cached under", vc_root)
        return
    for path in payload_paths:
        with zipfile.ZipFile(path) as archive:
            archive.extractall(vc_root)
    print("vc extraction complete under", vc_root)


# Content markers proving each SDK MSI actually extracted its payload.
# Maps an SDK_MSIS entry to one file that must exist after a complete
# administrative install; an earlier run without media cabinets produced
# partial trees, so presence of these markers (not cached MSIs) gates skipping.
SDK_MSI_MARKERS = {
    "Windows SDK Desktop Headers x64-x86_en-us.msi":
        "Include/10.0.19041.0/shared/ksamd64.inc",
    "Windows SDK for Windows Store Apps Headers-x86_en-us.msi":
        "Include/10.0.19041.0/um/Windows.h",
    "Windows SDK Desktop Headers x86-x86_en-us.msi":
        "Include/10.0.19041.0/winrt/MessageDispatcherApi.h",
    "Windows SDK Desktop Libs x64-x86_en-us.msi":
        "Lib/10.0.19041.0/um/x64/clusapi.lib",
    "Windows SDK Desktop Libs x86-x86_en-us.msi":
        "Lib/10.0.19041.0/um/x86/clusapi.lib",
    "Windows SDK for Windows Store Apps Libs-x86_en-us.msi":
        "Lib/10.0.19041.0/um/x64/kernel32.Lib",
    "Windows SDK Desktop Tools x64-x86_en-us.msi":
        "bin/10.0.19041.0/x64/tracelog.exe",
    "Windows SDK Desktop Tools x86-x86_en-us.msi":
        "bin/10.0.19041.0/x86/tracelog.exe",
    "Windows SDK Signing Tools-x86_en-us.msi":
        "bin/10.0.19041.0/x86/signtool.exe",
    "Windows SDK Modern Versioned Developer Tools-x86_en-us.msi":
        "bin/10.0.19041.0/x64/AppAnalysis/Microsoft.Diagnostics.AppAnalysis.dll",
    "Windows SDK Modern Non-Versioned Developer Tools-x86_en-us.msi":
        "bin/10.0.19041.0/XamlCompiler/x64/genxbf.dll",
    "Universal CRT Headers Libraries and Sources-x86_en-us.msi":
        "Lib/10.0.19041.0/ucrt/x64/ucrt.lib",
    "Universal CRT Redistributable-x86_en-us.msi":
        "Redist/10.0.19041.0/ucrt/DLLs/x64/ucrtbase.dll",
}


# Administratively installs one SDK MSI without elevation or registration.
#@param msi_path pathlib.Path Verified MSI file to extract.
#@param target_dir pathlib.Path Directory receiving the administrative image.
#@return None result No value; msiexec copies the feature files.
#@effect Launches msiexec /a up to four times, linking referenced media
#@effect cabinets between passes, and writes an administrative image under
#@effect target_dir; multi-pass extraction is required because a single
#@ msiexec pass resolves only part of the external media set.
def admin_install(msi_path, target_dir):
    marker = SDK_MSI_MARKERS.get(msi_path.name)
    marker_path = target_dir / "Windows Kits/10" / marker if marker else None
    if marker_path and marker_path.is_file():
        print("admin-install cached", msi_path.name)
        return
    log_path = target_dir.parent / (msi_path.name + ".admin.log")
    command = ["msiexec", "/a", str(msi_path), "/qn",
               "TARGETDIR=" + str(target_dir), "/l*v", str(log_path)]
    linked_total = 0
    for attempt in range(4):
        result = subprocess.run(command, capture_output=True)
        if result.returncode != 0:
            raise SystemExit("msiexec /a failed (%s) rc=%d" % (msi_path.name,
                                                               result.returncode))
        if marker_path and marker_path.is_file():
            break
        linked_total += link_media_from_log(log_path, msi_path.parent)
        if linked_total == 0 and attempt:
            break
    if marker and not marker_path.is_file():
        raise SystemExit("admin install incomplete for %s (missing %s)"
                         % (msi_path.name, marker))
    print("admin-installed", msi_path.name)


# Hardlinks media cabinets referenced by an msiexec log into the layout it wants.
#@param log_path pathlib.Path Verbose msiexec log (UTF-16) from admin_install.
#@param installers pathlib.Path Directory holding the plain hash-named cabs.
#@return int Number of new hardlinks created for referenced cabinets.
#@effect Creates <n>\<hash>.cab hardlinks under installers when missing.
def link_media_from_log(log_path, installers):
    text = log_path.read_text(encoding="utf-16", errors="replace")
    pattern = re.compile(r"MediaCabinet=([^,\s]+\.cab)")
    created = 0
    for cabinet in sorted(set(pattern.findall(text))):
        cabinet = cabinet.replace("/", "\\")
        target = installers / cabinet
        plain = installers / pathlib.PureWindowsPath(cabinet).name
        if target.exists() or not plain.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        os.link(plain, target)
        created += 1
    return created


# Runs the toolchain fetch and extraction pipeline for one cache directory.
#@param none No arguments; the cache directory arrives through sys.argv.
#@return None result No value; prints the digest record path on success.
#@effect Downloads ~450 MiB and writes downloads/, vc/ and sdk/ trees.
def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: fetch_v142_toolchain_windows.py CACHE_DIR")
    cache = pathlib.Path(sys.argv[1]).resolve()
    downloads = cache / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)

    channel_bytes = fetch_bytes(CHANNEL_URL)
    channel_digest = hashlib.sha256(channel_bytes).hexdigest()
    if channel_digest != CHANNEL_SHA256:
        raise SystemExit("channel manifest digest changed: %s (pinned %s); "
                         "re-verify upstream before re-pinning"
                         % (channel_digest, CHANNEL_SHA256))
    channel = json.loads(channel_bytes)
    product_entry = next(item for item in channel["channelItems"]
                         if item.get("id") == PRODUCT_ID)
    product_payload = product_entry["payloads"][0]
    if product_payload.get("sha256", "").lower() != PRODUCT_SHA256:
        raise SystemExit("product manifest digest drifted from pin")
    product = json.loads(fetch_bytes(product_payload["url"]))

    vc_paths = []
    vc_packages = set()
    buildtools_paths = []
    for package in product["packages"]:
        identity = package["id"]
        payloads = package.get("payloads", [])
        if identity in VC_IDS:
            vc_packages.add(identity)
            for payload in payloads:
                vc_paths.append(download_verified(payload["url"],
                                                  payload["fileName"],
                                                  payload["sha256"], downloads))
        if identity == BUILDTOOLS_ID:
            for payload in payloads:
                buildtools_paths.append(download_verified(payload["url"],
                                                          payload["fileName"],
                                                          payload["sha256"],
                                                          downloads))
        if identity == SDK_ID:
            for payload in payloads:
                download_verified(payload["url"], payload["fileName"],
                                  payload["sha256"], downloads)
    if vc_packages != set(VC_IDS):
        raise SystemExit("expected VC packages %s, resolved %s"
                         % (VC_IDS, sorted(vc_packages)))
    if len(buildtools_paths) != 1:
        raise SystemExit("expected 1 SDK buildtools payload, resolved %d"
                         % len(buildtools_paths))

    extract_vc(vc_paths, cache / "vc")
    buildtools_root = cache / "sdk-buildtools"
    buildtools_root.mkdir(parents=True, exist_ok=True)
    for path in buildtools_paths:
        with zipfile.ZipFile(path) as archive:
            archive.extractall(buildtools_root)
    print("sdk buildtools extracted under", buildtools_root)
    sdk_root = cache / "sdk"
    sdk_root.mkdir(parents=True, exist_ok=True)
    for name in SDK_MSIS:
        admin_install(downloads / "Installers" / name, sdk_root)

    msvc = cache / "vc/Contents/VC/Tools/MSVC/14.29.30133"
    kits = sdk_root / "Windows Kits/10"
    markers = (
        msvc / "bin/Hostx64/x64/cl.exe",
        msvc / "lib/x64/libcmt.lib",
        msvc / "lib/onecore/x64/msvcrt.lib",
        cache / "vc/Contents/VC/Redist/MSVC/14.29.30133/x64/Microsoft.VC142.CRT/vcruntime140.dll",
        cache / "sdk-buildtools/bin/10.0.19041.0/x64/rc.exe",
        kits / "Include/10.0.19041.0/um/Windows.h",
        kits / "Include/10.0.19041.0/ucrt/stdio.h",
        kits / "Lib/10.0.19041.0/um/x64/kernel32.Lib",
        kits / "Lib/10.0.19041.0/ucrt/x64/ucrt.lib",
        kits / "Redist/10.0.19041.0/ucrt/DLLs/x64/ucrtbase.dll",
    )
    for marker in markers:
        if not marker.is_file():
            raise SystemExit("missing extraction marker: %s" % marker)
    record = {path.name: file_sha256(path) for path in sorted(downloads.rglob("*"))
              if path.is_file()}
    record_path = cache / "payload-digests.json"
    record_path.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n",
                           encoding="utf-8")
    print("v142-toolchain=PASS payloads=%d record=%s" % (len(record), record_path))


if __name__ == "__main__":
    main()
