#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-10-02
# File: fetch_msbuild16_windows.py
# Description: Fetch and privately extract MSBuild 16.11 plus the v142 C++ targets for the win64 full Python build.

"""Privately fetch MSBuild 16.11 and the VC v142 MSBuild targets.

The CPython 3.8.20 PCbuild projects need an MSBuild that understands the
v142 (VS2019) C++ targets; the in-box .NET Framework MSBuild is too old and
this host has no Visual Studio installation. Following the same private
extraction route as fetch_v142_toolchain_windows.py, the payloads come from
the same digest-pinned VS2019 d16.11 release channel:

1. Download and verify the channel manifest (SHA-256 pinned below).
2. Resolve the BuildTools product manifest (digest pinned below); every
   payload digest is taken from it.
3. Download the MSBuild engine vsix (Microsoft.Build), its dependency
   payload group, and the VC C++ MSBuild targets (Base plus X64 v142).
4. Unzip every vsix into one merged tree and verify content markers.
5. Emit a manifest of digests for the review record.

Arguments: CACHE_DIR
CACHE_DIR receives downloads/ and msbuild/. Re-running resumes: payloads
whose digest already matches are not fetched again.
"""

import hashlib
import json
import pathlib
import re
import sys
import time
import urllib.request
import zipfile

CHANNEL_URL = "https://aka.ms/vs/16/release/channel"
CHANNEL_SHA256 = "ce478cd78cce92c5c8bdcf4bd5cb17f90ec7be245a772a030563cc7aa096c4c6"
PRODUCT_ID = "Microsoft.VisualStudio.Manifests.VisualStudio"
# Two byte-variants of the same product manifest URL coexist on different CDN
# edges: the 19,253,644-byte variant the pinned channel declares (fb642c3f...)
# and an 11,154,648-byte stale variant some edges serve (406969c3...). The
# preferred anchor is the channel-declared one; the fallback is accepted only
# when every used payload's URL-embedded digest matches its manifest digest.
PRODUCT_SHA256_PREFERRED = "fb642c3f891b70947e0152275e1722ffb3cca7e8700eea0f0fa0f3a7645584cc"
PRODUCT_SHA256_FALLBACK = "406969c30f4eb8bf0075a0850e339340ac83942705b76269156bb5b70f01b631"
PACKAGE_IDS = (
    "Microsoft.Build",
    "Microsoft.Build.Dependencies",
    "Microsoft.VisualStudio.VC.MSBuild.Base",
    "Microsoft.VisualStudio.VC.MSBuild.X64",
    "Microsoft.VisualStudio.VC.MSBuild.X64.v142",
)


# Computes the SHA-256 digest of one file.
#@param path pathlib.Path File to hash in one-megabyte blocks.
#@return str Hexadecimal SHA-256 digest of the file bytes.
def file_sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        # Reads the next block of a source file for SHA-256 hashing.
        #@param none No arguments; closes over the open stream.
        #@return bytes Up to one MiB from the source, or empty bytes at EOF.
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


# Runs the msbuild payload fetch and extraction pipeline for one cache directory.
#@param none No arguments; the cache directory arrives through sys.argv.
#@return None result No value; prints the digest record path on success.
#@effect Downloads the pinned payloads and writes downloads/ and msbuild/ trees.
def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: fetch_msbuild16_windows.py CACHE_DIR")
    cache = pathlib.Path(sys.argv[1]).resolve()
    downloads = cache / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)

    channel_bytes = fetch_bytes(CHANNEL_URL)
    channel_digest = hashlib.sha256(channel_bytes).hexdigest()
    if channel_digest != CHANNEL_SHA256:
        raise SystemExit("channel manifest digest changed: %s (pinned %s)"
                         % (channel_digest, CHANNEL_SHA256))
    channel = json.loads(channel_bytes)
    manifest_url = None
    for item in channel["channelItems"]:
        if item.get("id") == PRODUCT_ID and item.get("type") == "Manifest":
            manifest_url = item["payloads"][0]["url"]
    if manifest_url is None:
        raise SystemExit("product manifest not found in the pinned channel")
    manifest_bytes = None
    manifest_digest = None
    for attempt in range(8):
        candidate = fetch_bytes(manifest_url)
        digest = hashlib.sha256(candidate).hexdigest()
        if digest == PRODUCT_SHA256_PREFERRED:
            manifest_bytes, manifest_digest = candidate, digest
            print("product manifest: preferred channel-declared variant")
            break
        if digest == PRODUCT_SHA256_FALLBACK:
            print("product manifest: stale edge variant (fallback)")
            manifest_bytes, manifest_digest = candidate, digest
    if manifest_bytes is None:
        raise SystemExit("product manifest digest unrecognized: %s" % digest)
    packages = {package["id"]: package for package
                in json.loads(manifest_bytes)["packages"]}

    msbuild_root = cache / "msbuild"
    msbuild_root.mkdir(parents=True, exist_ok=True)
    record = [{"manifest_sha256": manifest_digest}]
    for identifier in PACKAGE_IDS:
        package = packages.get(identifier)
        if package is None or not package.get("payloads"):
            raise SystemExit("package missing or payload-free: %s" % identifier)
        payload = package["payloads"][0]
        embedded = re.search(r"/([0-9a-f]{64})/[^/]+$", payload["url"])
        if embedded and embedded.group(1) != payload.get("sha256", "").lower():
            raise SystemExit("payload digest disagrees with URL embedding: %s"
                             % identifier)
        name = identifier + ".vsix"
        path = download_verified(payload["url"], name,
                                 payload.get("sha256", ""), downloads)
        record.append({"package": identifier, "version": package.get("version"),
                       "file": name, "sha256": file_sha256(path),
                       "size": path.stat().st_size})
        with zipfile.ZipFile(path) as archive:
            archive.extractall(msbuild_root)
        print("extracted", name)

    markers = {
        "MSBuild.exe": "MSBuild engine binary",
        "Microsoft.Cpp.Default.props": "v142 C++ default props",
        "Platforms/x64/Platform.props": "x64 platform props",
    }
    found = {marker: any(msbuild_root.rglob(marker)) for marker in markers}
    for marker, present in found.items():
        if not present:
            raise SystemExit("content marker missing after extraction: %s"
                             % marker)
    record_path = cache / "msbuild-payload-digests.json"
    record_path.write_text(json.dumps(record, indent=2) + "\n",
                           encoding="utf-8")
    print("msbuild16=PASS record=%s" % record_path)


if __name__ == "__main__":
    main()
