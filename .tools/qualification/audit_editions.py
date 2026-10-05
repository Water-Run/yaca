#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: audit_editions.py
# Description: Verify final edition ZIP bytes, companion evidence and shared cores without executing payloads.

"""Audit explicit runtime/notices ZIP pairs on the build host.

An integrity pass records candidate bytes, not target qualification. Missing
build, test or license evidence remains visible in the JSON report.
"""

import argparse
import hashlib
import importlib.util
import json
import pathlib
import re
import stat
import struct
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("yaca_package_editions", ROOT / ".tools/package_editions.py")
PACKAGING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGING)
require = PACKAGING.require


# Hash an already opened file or ZIP member without buffering its full contents.
#@param source BinaryIO Caller-owned stream positioned at the first byte to hash.
#@return str Lowercase SHA-256 of bytes read through EOF.
#@effect Advances source to EOF; ZIP reads also validate the member CRC.
def stream_digest(source):
    value = hashlib.sha256()
    while True:
        chunk = source.read(1024 * 1024)
        if not chunk:
            return value.hexdigest()
        value.update(chunk)


# Decode a JSON object while rejecting duplicate keys that hide earlier evidence.
#@param pairs list[tuple[str,object]] Object members in their original JSON order.
#@return dict Object containing each admitted key exactly once.
#@error Raises ValueError if the object repeats a key.
def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


# Read a bounded UTF-8 evidence document from an admitted ZIP entry.
#@param archive ZipFile Caller-owned archive opened for reading.
#@param name str Exact member name previously admitted by inventory.
#@return str Decoded evidence text, at most 64 MiB before decoding.
#@error Raises ValueError or a ZIP/Unicode error for oversized or damaged evidence.
def document_text(archive, name):
    require(archive.getinfo(name).file_size <= 64 * 1024 * 1024, "evidence document too large: " + name)
    return archive.read(name).decode("utf-8")


# Read one evidence JSON document with unambiguous object keys.
#@param archive ZipFile Caller-owned archive opened for reading.
#@param name str Exact admitted evidence member name.
#@return object Parsed JSON document; its schema is validated by the caller.
#@error Raises for invalid UTF-8, malformed JSON or duplicate object keys.
def document_json(archive, name):
    return json.loads(document_text(archive, name), object_pairs_hook=unique_object)


# Admit regular normalized ZIP members and compute every member's digest.
#@param archive ZipFile Caller-owned archive opened for reading.
#@param case_sensitive bool True for Linux runtime members; false retains Windows/companion collision rejection.
#@return dict[str,dict] Member records with SHA-256, byte count and executable mode.
#@error Rejects unsafe paths, links, encrypted members, collisions or CRC failures.
#@effect Reads every uncompressed byte without extracting or executing the payload.
def inventory(archive, case_sensitive=False):
    result = {}
    members = archive.infolist()
    PACKAGING.validate_destinations([{"destination": PACKAGING.safe_destination(item.filename)}
                                     for item in members],case_sensitive)
    for item in members:
        mode = item.external_attr >> 16
        require(not item.is_dir() and stat.S_IFMT(mode) in (0, stat.S_IFREG),
                "ZIP member must be a regular file: " + item.filename)
        require(not item.flag_bits & 1, "encrypted ZIP member: " + item.filename)
        with archive.open(item) as source:
            value = stream_digest(source)
        result[item.filename] = {"sha256": value, "bytes": item.file_size,
                                 "executable": bool(mode & 0o111)}
    return result


# Check the packaged core's actual ELF or PE header against its declared target.
#@param archive ZipFile Runtime archive already admitted by inventory.
#@param name str Core executable member name.
#@param target str Canonical release target identifier.
#@return None No value; incompatible or malformed executable headers raise ValueError.
def validate_core(archive, name, target):
    with archive.open(name) as source:
        header = source.read(64)
        if target == "linux-x86_64":
            valid = len(header) >= 20 and header[:6] == b"\x7fELF\x02\x01" and header[18:20] == b"\x3e\x00"
        else:
            valid = False
            if len(header) == 64 and header[:2] == b"MZ":
                offset = struct.unpack_from("<I", header, 60)[0]
                require(offset <= 1024 * 1024, "invalid PE header offset")
                source.seek(offset)
                pe = source.read(26)
                machine, magic = (0x14c, 0x10b) if target == "win32-x86" else (0x8664, 0x20b)
                valid = len(pe) == 26 and pe[:4] == b"PE\0\0" and struct.unpack_from("<H", pe, 4)[0] == machine and struct.unpack_from("<H", pe, 24)[0] == magic
    require(valid, "core architecture differs from " + target)


# Extract available core evidence and list the remaining C34 evidence gaps.
#@param archive ZipFile Admitted companion notices archive.
#@param members dict[str,dict] Companion inventory containing verified member digests.
#@param summary dict Admitted edition metadata bound to the runtime ZIP bytes.
#@return dict Recorded source/build/test references and missing evidence names.
#@error Rejects a present build summary that belongs to a different target or core.
def core_evidence(archive, members, summary):
    missing = []
    build = {}
    if not any(name in members for name in ("core/LICENSE", "core/LICENSE.txt")):
        missing.append("core-product-license")
    if not any(name.endswith("/COMPONENTS.txt") for name in members):
        missing.append("core-component-license-manifest")
    sbom_names = [name for name in members if name.startswith("core/") and name.endswith("SBOM.spdx.json")]
    dependency_sbom = None
    if not sbom_names:
        missing.append("core-dependency-sbom")
    else:
        require(len(sbom_names) == 1, "ambiguous core dependency SBOM")
        dependency_sbom = document_json(archive, sbom_names[0])
        require(isinstance(dependency_sbom, dict) and dependency_sbom.get("spdxVersion") == "SPDX-2.3",
                "invalid core dependency SBOM")
        packages = dependency_sbom.get("packages")
        require(isinstance(packages, list) and all(isinstance(item, dict) for item in packages),
                "invalid core dependency packages")
        names = [item.get("name") for item in packages]
        require(all(isinstance(name, str) for name in names) and len(names) == len(set(names))
                and {"yaca", "luainstaller", "Lua", "LuaExpat", "Expat", "curl", "MbedTLS", "Mozilla-CA"} <= set(names),
                "incomplete core dependency SBOM")
        for item in packages:
            checksums = item.get("checksums", [])
            require(any(value.get("algorithm") == "SHA256" and isinstance(value.get("checksumValue"), str)
                        and re.fullmatch(r"[0-9a-f]{64}", value["checksumValue"]) for value in checksums),
                    "core dependency source SHA-256 missing: " + item["name"])
    if "core/docs/build-summary.json" in members:
        build = document_json(archive, "core/docs/build-summary.json")
        require(build.get("target") == summary["target"], "build summary target differs")
        hashes = [item.get("sha256") for item in build.get("artifacts", [])
                  if item.get("path") in ("package/yaca.exe", "package/yaca")]
        require(hashes == [summary["core_sha256"]], "build summary core differs")
        revision = build.get("base_revision")
        snapshot = build.get("source_snapshot_sha256")
        full_tests = build.get("full_tests")
    elif "core/build-summary.txt" in members or "core/docs/build-summary.txt" in members:
        name = "core/build-summary.txt" if "core/build-summary.txt" in members else "core/docs/build-summary.txt"
        for line in document_text(archive, name).splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                require(key not in build, "duplicate build summary field: " + key)
                build[key] = value
        require(build.get("target") == summary["target"], "build summary target differs")
        revision = build.get("yaca_revision")
        snapshot = build.get("yaca_archive_sha256")
        full_tests = build.get("full_tests")
    else:
        missing.append("core-build-summary")
        revision, snapshot, full_tests = None, None, None
    if build and build.get("status") not in ("PASS", "cross-build-passed", "assembled"):
        missing.append("core-successful-build-status")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        missing.append("core-source-revision")
    if not isinstance(snapshot, str) or not re.fullmatch(r"[0-9a-f]{64}", snapshot):
        missing.append("core-source-snapshot-sha256")
    elif dependency_sbom:
        source_package = next(item for item in dependency_sbom["packages"] if item["name"] == "yaca")
        require({"algorithm": "SHA256", "checksumValue": snapshot} in source_package["checksums"],
                "core dependency SBOM source snapshot differs")
    match = re.fullmatch(r"([1-9][0-9]*)/([1-9][0-9]*)", str(full_tests))
    if not match or match[1] != match[2]:
        missing.append("core-full-test-summary")
    return {"source_revision": revision, "source_snapshot_sha256": snapshot,
            "full_tests": full_tests, "missing": missing}


# Verify one final runtime ZIP against its companion metadata and locked catalog.
#@param package_path Path|str Explicit runtime archive; its basename must match edition metadata.
#@param notices_path Path|str Explicit companion archive for the same target and edition.
#@param catalog_path Path|str Current tool catalog used to verify versions and catalog SHA-256.
#@return dict Byte-bound integrity report retaining unqualified status and evidence gaps.
#@error Raises on any corrupt byte, metadata mismatch, unsafe layout or SBOM disagreement.
#@effect Reads both ZIPs and the catalog; never extracts, executes, fetches or authorizes release.
def audit_pair(package_path, notices_path, catalog_path=ROOT / "release/tool-bundles.json"):
    package_path = PACKAGING.regular_file(package_path)
    notices_path = PACKAGING.regular_file(notices_path)
    catalog = json.loads(PACKAGING.regular_file(catalog_path).read_text(encoding="utf-8"),
                         object_pairs_hook=unique_object)
    require(catalog.get("schema") == "yaca-tool-catalog-v1", "unsupported tool catalog")
    package_sha = PACKAGING.digest(package_path)
    notices_sha = PACKAGING.digest(notices_path)
    with zipfile.ZipFile(package_path) as payload, zipfile.ZipFile(notices_path) as notices:
        companions = inventory(notices)
        require("edition.json" in companions and "SBOM.spdx.json" in companions, "missing edition metadata or SBOM")
        summary = document_json(notices, "edition.json")
        require(isinstance(summary, dict) and summary.get("schema") == "yaca-edition-v1", "unsupported edition metadata")
        require(summary.get("status") == "candidate-unqualified"
                and summary.get("release_authorized") is False
                and summary.get("target_qualification_complete") is False,
                "audit accepts unqualified candidates only")
        target, edition = summary.get("target"), summary.get("edition")
        require(isinstance(target, str) and target in catalog["targets"], "unknown edition target")
        require(isinstance(edition, str) and edition in catalog["editions"], "unknown edition")
        version = summary.get("version")
        require(isinstance(version, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", version), "invalid edition version")
        stem = "yaca-" + version + "-" + target + "-" + edition
        require(package_path.name == stem + ".zip" and notices_path.name == stem + "-notices.zip", "archive names differ from metadata")
        require(summary.get("archive_sha256") == package_sha, "runtime archive SHA-256 differs")
        require(summary.get("catalog_sha256") == PACKAGING.digest(catalog_path), "edition catalog SHA-256 differs")
        records = summary.get("files")
        require(isinstance(records, list) and all(isinstance(item, dict) for item in records), "invalid edition file records")
        files = inventory(payload,case_sensitive=target=="linux-x86_64")
        PACKAGING.validate_destinations(records,case_sensitive=target=="linux-x86_64")
        expected = {PACKAGING.safe_destination(item["destination"]): item for item in records}
        require(set(files) == set(expected), "runtime member inventory differs")
        for name, actual in files.items():
            record = expected[name]
            require(actual["sha256"] == record.get("sha256"), "runtime file SHA-256 differs: " + name)
            require(type(record.get("executable")) is bool and actual["executable"] == record["executable"],
                    "runtime executable mode differs: " + name)
        definition = catalog["targets"][target]
        executable = definition["executable"]
        require(executable in files and files[executable]["executable"], "core executable is missing or not executable")
        require(files[executable]["sha256"] == summary.get("core_sha256"), "core SHA-256 differs")
        validate_core(payload, executable, target)
        tools = summary.get("tools")
        require(isinstance(tools, list) and all(isinstance(item, dict) for item in tools), "invalid tool records")
        require([item.get("id") for item in tools] == catalog["editions"][edition], "edition tool list differs from catalog")
        allowed = {executable}
        sources = set()
        tool_gaps = []
        for tool in tools:
            tool_id = tool["id"]
            specification = catalog["tools"][tool_id]
            prefix = "tools/" + specification["directory"] + "/"
            require(tool.get("version") == definition["versions"].get(tool_id, specification.get("version")),
                    "tool version differs: " + tool_id)
            owned = {name for name in files if name.startswith(prefix)}
            require(owned, "tool payload missing: " + tool_id)
            allowed.update(owned)
            if tool_id == "git":
                leaves = {pathlib.PurePosixPath(name).name for name in owned}
                for helper in ("git-remote-http", "git-remote-https"):
                    if helper not in leaves and helper + ".exe" not in leaves:
                        tool_gaps.append(helper)
            for field in ("entry_points", "license_files"):
                names = tool.get(field)
                require(isinstance(names, list) and names and all(isinstance(name, str) and name in owned
                        and files[name]["bytes"] > 0 for name in names), "tool " + field + " missing: " + tool_id)
            require(isinstance(tool.get("license_id"), str) and tool["license_id"], "tool license identifier missing")
            require(isinstance(tool.get("source_url"), str) and tool["source_url"].startswith("https://"), "tool source URL missing")
            source = tool.get("source_archive")
            require(isinstance(source, dict), "tool source archive missing: " + tool_id)
            name = PACKAGING.safe_destination(source.get("destination"))
            require(name.startswith("sources/" + tool_id + "/") and name in companions
                    and companions[name]["sha256"] == source.get("sha256"), "tool source SHA-256 differs: " + tool_id)
            sources.add(name)
        if edition != "clean":
            require("tools/README.txt" in files, "toolbox README missing")
            allowed.update(("tools/README.txt", "tools/INDEX.txt"))
        require(set(files) <= allowed, "unexpected runtime surface")
        require(all(name.startswith("core/") or name in sources or name in ("edition.json", "SBOM.spdx.json")
                    for name in companions), "unexpected companion surface")
        sbom = document_json(notices, "SBOM.spdx.json")
        require(sbom == PACKAGING.edition_sbom(summary), "edition SBOM differs from verified metadata")
        evidence = core_evidence(notices, companions, summary)
    require(PACKAGING.digest(package_path) == package_sha and PACKAGING.digest(notices_path) == notices_sha,
            "archive changed during audit")
    return {"target": target, "edition": edition, "version": version,
            "archive": str(package_path), "archive_sha256": package_sha,
            "notices": str(notices_path), "notices_sha256": notices_sha,
            "core_sha256": summary["core_sha256"], "files": len(files), "tools": len(tools),
            "core_evidence": evidence, "tool_payload_gaps": tool_gaps,
            "integrity": "passed", "qualification": "pending"}


# Combine verified pairs while enforcing equal cores and one version per target.
#@param pairs list[dict] Reports produced by audit_pair, one per target/edition.
#@param catalog_path Path|str Catalog defining the required three-by-three matrix.
#@return dict Aggregate candidate report including missing pairs and C34 evidence gaps.
#@error Rejects duplicate pairs, mixed versions or different cores within one target.
def aggregate(pairs, catalog_path=ROOT / "release/tool-bundles.json"):
    catalog = json.loads(PACKAGING.regular_file(catalog_path).read_text(encoding="utf-8"))
    seen = set()
    cores = {}
    versions = set()
    for pair in pairs:
        key = (pair["target"], pair["edition"])
        require(key not in seen, "duplicate target/edition pair")
        seen.add(key)
        target = pair["target"]
        require(target not in cores or cores[target] == pair["core_sha256"], "edition cores differ: " + target)
        cores[target] = pair["core_sha256"]
        versions.add(pair["version"])
    require(len(versions) <= 1, "edition versions differ")
    missing = [target + "/" + edition for target in catalog["targets"] for edition in catalog["editions"]
               if (target, edition) not in seen]
    return {"schema": "yaca-edition-audit-v1", "status": "verified-unqualified",
            "release_authorized": False, "target_qualification_complete": False,
            "pairs": pairs, "missing_pairs": missing, "shared_cores": cores,
            "evidence_complete": bool(pairs) and not missing
                and all(not pair["core_evidence"]["missing"] and not pair["tool_payload_gaps"] for pair in pairs)}


# Audit selected pairs and optionally require the full matrix and C34 documents.
#@param none No arguments; reads the process command line through argparse.
#@return None No value; exits nonzero for damaged archives or unmet required evidence.
#@effect Reads explicit files, prints a concise result and optionally creates a JSON report.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pair", nargs=2, action="append", required=True, metavar=("RUNTIME_ZIP", "NOTICES_ZIP"))
    parser.add_argument("--catalog", type=pathlib.Path, default=ROOT / "release/tool-bundles.json")
    parser.add_argument("--output", type=pathlib.Path, help="new JSON report path; existing files are not replaced")
    parser.add_argument("--require-nine", action="store_true")
    parser.add_argument("--require-evidence", action="store_true")
    args = parser.parse_args()
    try:
        report = aggregate([audit_pair(package, notices, args.catalog) for package, notices in args.pair], args.catalog)
        if args.output:
            with args.output.open("x", encoding="utf-8") as output:
                output.write(json.dumps(report, indent=2) + "\n")
        require(not args.require_nine or not report["missing_pairs"], "nine-pair matrix incomplete")
        require(not args.require_evidence or report["evidence_complete"], "C34 evidence incomplete; see report")
    except (ValueError, KeyError, TypeError, AttributeError, OSError, zipfile.BadZipFile, RuntimeError) as error:
        parser.exit(1, "edition-audit=FAIL " + str(error) + "\n")
    print("edition-audit=PASS pairs=" + str(len(report["pairs"]))
          + " missing-pairs=" + str(len(report["missing_pairs"]))
          + " evidence-complete=" + str(report["evidence_complete"]).lower()
          + " qualification=pending")


if __name__ == "__main__":
    main()
