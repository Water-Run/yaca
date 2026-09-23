#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: editions_test.py
# Description: Build-host integration tests for edition payloads, provenance and failures.

"""Build-host integration tests for edition payloads, provenance and failures."""

import copy
import hashlib
import importlib.util
import json
import pathlib
import struct
import tempfile
import types
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("editions", ROOT / ".tools/package_editions.py")
editions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(editions)


##@class EditionTest Isolated package-assembly tests using a disposable PE and tool catalog.
##@field root pathlib.Path Temporary fixture directory owned by each test instance.
##@field inputs dict Tool provenance input document mutated by negative cases.
##@field args types.SimpleNamespace Edition assembly arguments targeting the temporary directory.
class EditionTest(unittest.TestCase):
    # Build a disposable Windows core and pinned tool-input fixture.
    #@param self EditionTest Per-test fixture owner.
    #@return None No value; fixture state is stored on the test instance.
    #@effect Writes temporary fixture inputs and registers their cleanup.
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="edition test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.catalog = json.loads((ROOT / "release/tool-bundles.json").read_text())
        header = bytearray(128)
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 60, 64)
        header[64:68] = b"PE\0\0"
        struct.pack_into("<H", header, 68, 0x14c)
        struct.pack_into("<H", header, 88, 0x10b)
        (self.root / "core.exe").write_bytes(header)
        (self.root / "notices").mkdir()
        (self.root / "notices/LICENSE").write_text("fixture license\n")
        inputs = {"schema": "yaca-tool-inputs-v1", "target": "win32-x86", "tools": []}
        for name in self.catalog["editions"]["full"]:
            definition = self.catalog["tools"][name]
            prefix = "tools/" + definition["directory"] + "/"
            version = self.catalog["targets"]["win32-x86"]["versions"].get(name, definition.get("version"))
            program = self.file(name + ".exe", prefix + name + ".exe", b"fixture program")
            license_file = self.file(name + "-license", prefix + "LICENSE", b"fixture notice")
            source = self.file(name + "-source.tar", "unused", b"fixture source archive")
            inputs["tools"].append({"id": name, "version": version, "files": [program, license_file],
                                    "entry_points": [program["destination"]], "license_id": "MIT",
                                    "license_files": [license_file["destination"]],
                                    "source_url": "https://example.test/source", "source_archive": source})
        self.inputs = inputs
        self.save()
        self.args = types.SimpleNamespace(catalog=ROOT / "release/tool-bundles.json", target="win32-x86",
                                         core=self.root / "core.exe", core_sha256=editions.digest(self.root / "core.exe"),
                                         core_notices=self.root / "notices", tool_inputs=self.root / "inputs.json",
                                         edition="all", version="fixture", output=self.root / "output")

    # Write a fixture payload and describe its verified package destination.
    #@param self EditionTest Per-test fixture owner.
    #@param name str Temporary source filename.
    #@param destination str Destination inside an edition archive.
    #@param content bytes Exact fixture payload bytes.
    #@return dict Payload source, destination, and SHA-256 digest.
    #@effect Writes one file beneath the temporary fixture directory.
    def file(self, name, destination, content):
        (self.root / name).write_bytes(content)
        return {"source": name, "destination": destination, "sha256": hashlib.sha256(content).hexdigest()}

    # Persist the current tool-input document for the next assembly call.
    #@param self EditionTest Per-test fixture owner.
    #@return None No value; the document is written to the fixture directory.
    #@effect Replaces the temporary inputs.json fixture.
    def save(self):
        (self.root / "inputs.json").write_text(json.dumps(self.inputs))

    # Check archive roots, shared executable hash, notices, and per-file digests.
    #@param self EditionTest Per-test fixture owner.
    #@return None Assertions fail if any edition payload or provenance differs.
    def test_three_editions_share_core_and_have_exact_roots(self):
        summaries = editions.assemble(self.args)
        self.assertEqual([item["edition"] for item in summaries], ["clean", "std", "full"])
        for item in summaries:
            stem = "yaca-fixture-win32-x86-" + item["edition"]
            with zipfile.ZipFile(self.args.output / (stem + ".zip")) as archive:
                self.assertEqual(hashlib.sha256(archive.read("yaca.exe")).hexdigest(), self.args.core_sha256)
                roots = {name.split("/")[0] for name in archive.namelist()}
                self.assertEqual(roots, {"yaca.exe"} if item["edition"] == "clean" else {"yaca.exe", "tools"})
                if item["edition"] != "clean":
                    self.assertIn(b"Python", archive.read("tools/README.txt"))
            with zipfile.ZipFile(self.args.output / (stem + "-notices.zip")) as archive:
                self.assertIn("core/LICENSE", archive.namelist())
                self.assertFalse(json.loads(archive.read("edition.json"))["release_authorized"])
                sbom = json.loads(archive.read("SBOM.spdx.json"))
                self.assertEqual(len(sbom["packages"]), len(item["tools"]) + 1)
                self.assertEqual(len(sbom["files"]), len(item["files"]))
                for tool in item["tools"]:
                    source = tool["source_archive"]
                    self.assertEqual(hashlib.sha256(archive.read(source["destination"])).hexdigest(), source["sha256"])
            with zipfile.ZipFile(self.args.output / (stem + ".zip")) as archive:
                self.assertEqual(set(archive.namelist()), {entry["destination"] for entry in item["files"]})
                for entry in item["files"]:
                    self.assertEqual(hashlib.sha256(archive.read(entry["destination"])).hexdigest(), entry["sha256"])
            self.assertEqual(len(item["tools"]), len(self.catalog["editions"][item["edition"]]))

    # Check that missing or modified tools abort assembly before output appears.
    #@param self EditionTest Per-test fixture owner.
    #@return None Assertions fail on a partial or accepted corrupt distribution.
    def test_missing_and_modified_tools_produce_no_partial_distribution(self):
        self.inputs["tools"].pop()
        self.save()
        with self.assertRaisesRegex(ValueError, "missing tools"):
            editions.assemble(self.args)
        self.assertFalse(self.args.output.exists())
        (self.root / "python2.exe").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            editions.assemble(self.args)

    # Check target, pinned version, and core architecture mismatch rejection.
    #@param self EditionTest Per-test fixture owner.
    #@return None Assertions fail if incompatible inputs are accepted.
    def test_target_and_version_mismatches_are_rejected(self):
        self.inputs["target"] = "win64-x86_64"
        self.save()
        with self.assertRaisesRegex(ValueError, "different target"):
            editions.assemble(self.args)
        self.inputs["target"] = "win32-x86"
        self.inputs["tools"][0]["version"] = "2.7.17"
        self.save()
        with self.assertRaisesRegex(ValueError, "version differs"):
            editions.assemble(self.args)
        self.args.target = "win64-x86_64"
        with self.assertRaisesRegex(ValueError, "architecture"):
            editions.assemble(self.args)

    # Check that clean assembly needs no tool inputs but still hashes the core.
    #@param self EditionTest Per-test fixture owner.
    #@return None Assertions fail if the clean edition bypasses core integrity.
    def test_clean_requires_no_tool_inputs_and_preserves_core_hash_check(self):
        self.args.edition = "clean"
        self.args.tool_inputs = None
        self.args.core_sha256 = "0" * 64
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            editions.assemble(self.args)
        self.args.core_sha256 = editions.digest(self.args.core)
        self.assertEqual(len(editions.assemble(self.args)), 1)

    # Check unsafe package paths, linked cores, and case-folded collisions.
    #@param self EditionTest Per-test fixture owner.
    #@return None Assertions fail if an unsafe package input is accepted.
    def test_unsafe_paths_symlinks_and_case_collisions_are_rejected(self):
        original = copy.deepcopy(self.inputs)
        for path in ("../yaca.exe", "/tools/a", "tools/NUL.txt", "tools/a:stream", "tools/a "):
            with self.subTest(path=path):
                self.inputs = copy.deepcopy(original)
                self.inputs["tools"][0]["files"][0]["destination"] = path
                self.save()
                with self.assertRaises(ValueError):
                    editions.assemble(self.args)
        (self.root / "link").symlink_to(self.root / "core.exe")
        self.args.edition = "clean"
        self.args.core = self.root / "link"
        with self.assertRaisesRegex(ValueError, "symlink"):
            editions.assemble(self.args)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            editions.validate_destinations([{"destination": "tools/a"}, {"destination": "tools/A"}])


if __name__ == "__main__":
    unittest.main()
