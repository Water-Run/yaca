#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: package_editions.py
# Description: Assemble portable candidate editions from explicit, hashed target inputs.

"""Assemble portable candidate editions from explicit, hashed target inputs.

This is a build-host utility, never a yaca runtime dependency. It neither fetches
nor executes toolbox programs and never promotes a candidate to a qualified release.
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import struct
import tempfile
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]


# Rejects a packaging precondition with its specific diagnostic.
#@param condition bool Precondition that must hold.
#@param message str Assertion or diagnostic message.
#@return None result No value; raises ValueError when a package precondition fails.
def require(condition, message):
    if not condition:
        raise ValueError(message)


# Validates a normalized relative destination inside an edition archive.
#@param value object Candidate value under validation.
#@return str destination Normalized safe relative archive destination.
def safe_destination(value):
    require(isinstance(value, str) and value and "\\" not in value,
            "destination must be a relative forward-slash path")
    parts = value.split("/")
    for part in parts:
        require(part not in ("", ".", "..") and not part.endswith((".", " "))
                and not re.search(r'[\x00-\x1f<>:"|?*]', part)
                and not re.fullmatch(r"(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", part),
                "unsafe destination: " + value)
    return value


# Rejects linked or nonregular package input files.
#@param path Path|str Input file or package path under inspection.
#@return Path file Admitted regular input file path.
def regular_file(path):
    path = pathlib.Path(path).absolute()
    require(not any(item.is_symlink() for item in (path, *path.parents)),
            "symlink inputs are not allowed: " + str(path))
    require(path.is_file(), "input file is missing: " + str(path))
    return path


# Computes the SHA-256 digest of one input file.
#@param path Path|str Input file or package path under inspection.
#@return str digest Lowercase SHA-256 digest of the input file.
def digest(path):
    value = hashlib.sha256()
    with regular_file(path).open("rb") as source:
        # Reads the next block of the package input for SHA-256 hashing.
        #@param none No arguments.
        #@return bytes Up to one MiB from source, or empty bytes at EOF.
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


# Checks the executable architecture and target-specific core metadata.
#@param path Path|str Input file or package path under inspection.
#@param target str|dict Selected release target or destination.
#@return None result No value; raises if executable headers disagree with the target.
def validate_core(path, target):
    with regular_file(path).open("rb") as source:
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
    require(valid, "core executable architecture does not match " + target)


# Builds a verified package file record from one input.
#@param base object The base supplied to this proof operation.
#@param record dict Artifact or package file record.
#@param destination str Relative destination inside the package.
#@return dict record Verified file record for one package payload.
def file_record(base, record, destination=None):
    require(isinstance(record, dict) and set(record) <= {"source", "destination", "sha256", "executable"},
            "invalid file record")
    expected = record.get("sha256", "")
    require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected), "file SHA-256 is required")
    source = regular_file(base / record["source"])
    require(digest(source) == expected, "SHA-256 mismatch: " + str(source))
    return {"source": source, "destination": safe_destination(destination or record["destination"]),
            "sha256": expected, "executable": record.get("executable", False)}


# Rejects duplicate and unsafe archive destinations.
#@param files list[dict] Verified files to place in the archive.
#@return None result No value; raises on unsafe or colliding archive paths.
def validate_destinations(files):
    seen = set()
    names = {item["destination"].casefold() for item in files}
    for item in files:
        name = item["destination"].casefold()
        require(name not in seen, "duplicate destination: " + item["destination"])
        require(not any(str(parent) in names for parent in pathlib.PurePosixPath(name).parents),
                "file/directory destination collision: " + name)
        seen.add(name)


# Writes a deterministic ZIP archive from verified payload records.
#@param path Path|str Input file or package path under inspection.
#@param files list[dict] Verified files to place in the archive.
#@param generated dict Generated metadata files for the archive.
#@return None result No value; writes the verified deterministic ZIP archive.
def write_archive(path, files, generated=None):
    validate_destinations(files + [{"destination": safe_destination(name)} for name in generated or {}])
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        # Orders package entries by their normalized archive destination.
        #@param value dict Verified source and destination record.
        #@return str Destination path used as the ZIP entry sort key.
        for item in sorted(files, key=lambda value: value["destination"]):
            info = zipfile.ZipInfo(item["destination"], (2000, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | (0o755 if item["executable"] else 0o644)) << 16
            actual = hashlib.sha256()
            with regular_file(item["source"]).open("rb") as source, archive.open(info, "w") as output:
                # Reads the next block while copying a package source file.
                #@param none No arguments.
                #@return bytes Up to one MiB from source, or empty bytes at EOF.
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    actual.update(chunk)
                    output.write(chunk)
            require(actual.hexdigest() == item["sha256"], "input changed while packaging: " + str(item["source"]))
        for name, content in sorted((generated or {}).items()):
            info = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            archive.writestr(info, content)


# Builds an SPDX document for one edition's core and tools.
#@param summary dict Edition inventory used for SPDX generation.
#@return dict sbom SPDX document for the selected edition.
def edition_sbom(summary):
    """Describe edition payloads; core dependency detail stays in its companion SBOM."""
    packages = [{"SPDXID": "SPDXRef-yaca", "name": "yaca", "versionInfo": summary["version"],
                 "downloadLocation": "NOASSERTION", "filesAnalyzed": False,
                 "licenseConcluded": "NOASSERTION", "licenseDeclared": "GPL-3.0-only",
                 "copyrightText": "NOASSERTION",
                 "checksums": [{"algorithm": "SHA256", "checksumValue": summary["core_sha256"]}],
                 "sourceInfo": "Core runtime binary. See core/ for dependency SBOM, notices and source references."}]
    relationships = [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES",
                      "relatedSpdxElement": "SPDXRef-yaca"}]
    for tool in summary["tools"]:
        identifier = "SPDXRef-tool-" + tool["id"]
        # Non-SPDX vendor license identifiers remain in edition.json and the
        # shipped license text instead of inventing SPDX extracted-license IDs.
        declared = tool["license_id"] if "LicenseRef-" not in tool["license_id"] else "NOASSERTION"
        packages.append({"SPDXID": identifier, "name": tool["id"], "versionInfo": tool["version"],
                         "downloadLocation": tool["source_url"], "filesAnalyzed": False,
                         "licenseConcluded": "NOASSERTION", "licenseDeclared": declared,
                         "copyrightText": "NOASSERTION",
                         "sourceInfo": "Corresponding source: " + tool["source_archive"]["destination"]
                            + "; SHA256=" + tool["source_archive"]["sha256"]
                            + ". Target qualification pending. Licenses: " + ", ".join(tool["license_files"])})
        relationships.append({"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES",
                              "relatedSpdxElement": identifier})
    files = []
    for index, item in enumerate(summary["files"]):
        identifier = "SPDXRef-file-" + str(index)
        files.append({"SPDXID": identifier, "fileName": "./" + item["destination"],
                      "checksums": [{"algorithm": "SHA256", "checksumValue": item["sha256"]}],
                      "licenseConcluded": "NOASSERTION", "licenseInfoInFiles": ["NOASSERTION"],
                      "copyrightText": "NOASSERTION"})
        relationships.append({"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES",
                              "relatedSpdxElement": identifier})
    return {"spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
            "name": "yaca " + summary["target"] + " " + summary["edition"] + " candidate payloads",
            "documentNamespace": "https://github.com/Water-Run/yaca/editions/" + summary["archive_sha256"],
            "creationInfo": {"creators": ["Tool: yaca-edition-assembler"], "created": "2026-09-22T00:00:00Z"},
            "packages": packages, "files": files, "relationships": relationships}


# Assembles clean, std, or full editions from pinned inputs.
#@param args Namespace Parsed command-line arguments.
#@return list[dict] summaries Published edition summaries.
def assemble(args):
    catalog = json.loads(regular_file(args.catalog).read_text(encoding="utf-8"))
    require(catalog["schema"] == "yaca-tool-catalog-v1", "unsupported tool catalog")
    target = catalog["targets"][args.target]
    editions = list(catalog["editions"]) if args.edition == "all" else [args.edition]
    require(set(editions) <= {"clean", "std", "full"}, "invalid edition")
    core = file_record(pathlib.Path.cwd(), {"source": str(args.core), "sha256": args.core_sha256,
                                          "destination": target["executable"], "executable": True})
    validate_core(core["source"], args.target)
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.version), "unsafe version")
    notices_root = pathlib.Path(args.core_notices).absolute()
    require(notices_root.is_dir() and not notices_root.is_symlink(), "core notices directory is required")
    notice_files = []
    for path in sorted(notices_root.rglob("*")):
        require(not path.is_symlink(), "symlink in core notices")
        if path.is_file():
            notice_files.append(file_record(notices_root, {
                "source": str(path), "sha256": digest(path),
                "destination": "core/" + path.relative_to(notices_root).as_posix()}))
    require(notice_files and any("license" in item["destination"].lower() for item in notice_files),
            "core licenses must accompany every edition")
    required = {tool for edition in editions for tool in catalog["editions"][edition]}
    admitted = {}
    if required:
        require(args.tool_inputs is not None, "std/full require hashed target tool inputs; no placeholder edition is produced")
        input_path = regular_file(args.tool_inputs)
        inputs = json.loads(input_path.read_text(encoding="utf-8"))
        require(inputs["schema"] == "yaca-tool-inputs-v1" and inputs["target"] == args.target,
                "tool inputs belong to a different target or schema")
        for item in inputs["tools"]:
            tool_id = item["id"]
            require(tool_id in catalog["tools"] and tool_id not in admitted, "unknown or repeated tool: " + tool_id)
            specification = catalog["tools"][tool_id]
            expected = target["versions"].get(tool_id, specification.get("version"))
            require(item["version"] == expected, "tool version differs from catalog: " + tool_id)
            files = [file_record(input_path.parent, value) for value in item["files"]]
            prefix = "tools/" + specification["directory"] + "/"
            require(files and all(value["destination"].startswith(prefix) for value in files),
                    "tool files must stay in their own directory: " + tool_id)
            destinations = {value["destination"] for value in files}
            require(item["entry_points"] and all(name in destinations for name in item["entry_points"]),
                    "declared tool entry point is missing: " + tool_id)
            require(item["license_id"] and item["license_files"]
                    and all(name in destinations for name in item["license_files"]),
                    "tool license files are missing: " + tool_id)
            require(item["source_url"].startswith("https://"), "tool source URL is required")
            source = file_record(input_path.parent, item["source_archive"],
                                 "sources/" + tool_id + "/" + pathlib.Path(item["source_archive"]["source"]).name)
            admitted[tool_id] = {"metadata": item, "files": files, "source": source}
        require(required <= admitted.keys(), "missing tools: " + ", ".join(sorted(required - admitted.keys())))

    destination = pathlib.Path(args.output).absolute()
    require(not destination.exists(), "output already exists")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".yaca-editions-", dir=destination.parent) as temporary:
        stage = pathlib.Path(temporary)
        summaries = []
        for edition in editions:
            stem = "yaca-" + args.version + "-" + args.target + "-" + edition
            files = [core]
            notices = list(notice_files)
            descriptions = ["yaca optional toolbox (" + args.target + ", " + edition + ")", "",
                            "Use explicit executable paths through exec. Nothing is installed or added to PATH.",
                            "These are candidate artifacts; consult the companion evidence for tested systems.", ""]
            tool_metadata = []
            for tool_id in catalog["editions"][edition]:
                tool = admitted[tool_id]
                item = tool["metadata"]
                files.extend(tool["files"])
                notices.append(tool["source"])
                descriptions.extend([tool_id + " " + item["version"], catalog["tools"][tool_id]["purpose"],
                                     "Entry points: " + ", ".join(item["entry_points"]), ""])
                metadata = {key: item[key] for key in
                            ("id", "version", "entry_points", "license_id", "license_files", "source_url")}
                metadata["source_archive"] = {key: tool["source"][key] for key in ("destination", "sha256")}
                tool_metadata.append(metadata)
            descriptions.extend(target["notes"])
            generated = {} if edition == "clean" else {"tools/README.txt": "\n".join(descriptions) + "\n"}
            write_archive(stage / (stem + ".zip"), files, generated)
            summary = {"schema": "yaca-edition-v1", "target": args.target, "edition": edition,
                       "version": args.version, "core_sha256": core["sha256"],
                       "status": "candidate-unqualified", "release_authorized": False,
                       "target_qualification_complete": False, "tools": tool_metadata,
                       "files": [{key: value for key, value in item.items() if key != "source"} for item in files]}
            summary["catalog_sha256"] = digest(args.catalog)
            for name, content in generated.items():
                summary["files"].append({"destination": name,
                    "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(), "executable": False})
            summary["archive_sha256"] = digest(stage / (stem + ".zip"))
            write_archive(stage / (stem + "-notices.zip"), notices,
                          {"edition.json": json.dumps(summary, indent=2) + "\n",
                           "SBOM.spdx.json": json.dumps(edition_sbom(summary), indent=2) + "\n"})
            summaries.append(summary)
        require(len({item["core_sha256"] for item in summaries}) == 1, "edition cores differ")
        (stage / "SHA256SUMS.txt").write_text("".join(
            digest(path) + "  " + path.name + "\n" for path in sorted(stage.glob("*.zip"))), encoding="ascii")
        (stage / "editions.json").write_text(json.dumps(summaries, indent=2) + "\n", encoding="utf-8")
        os.rename(stage, destination)
    return summaries


# Runs the package editions command and reports its status.
#@param none No arguments.
#@return None result No value; argparse or assembly failures terminate the CLI.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=pathlib.Path, default=ROOT / "release/tool-bundles.json")
    parser.add_argument("--target", required=True, choices=["win32-x86", "win64-x86_64", "linux-x86_64"])
    parser.add_argument("--core", type=pathlib.Path, required=True)
    parser.add_argument("--core-sha256", required=True)
    parser.add_argument("--core-notices", type=pathlib.Path, required=True)
    parser.add_argument("--tool-inputs", type=pathlib.Path)
    parser.add_argument("--version", default="0.1.0-preview")
    parser.add_argument("--edition", choices=["all", "clean", "std", "full"], default="all")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        results = assemble(args)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, "package editions: " + str(error) + "\n")
    print("editions=PASS target=" + args.target + " editions=" + ",".join(item["edition"] for item in results))


if __name__ == "__main__":
    main()
