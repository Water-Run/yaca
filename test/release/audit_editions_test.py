#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: audit_editions_test.py
# Description: Reject damaged edition payloads, forged companion evidence and inconsistent release matrices.

import copy
import hashlib
import importlib.util
import json
import pathlib
import stat
import subprocess
import sys
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("audit_editions", ROOT / ".tools/qualification/audit_editions.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)
SPEC = importlib.util.spec_from_file_location("edition_fixtures", ROOT / "test/release/editions_test.py")
FIXTURES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURES)


#@class AuditTest Byte-level package audit tests with isolated disposable assembler inputs.
#@field fixture EditionTest Owns the temporary core, tool payloads and fixture cleanup.
#@field pairs list[tuple[Path,Path]] Clean/std/full runtime and companion paths.
class AuditTest(unittest.TestCase):
    # Assemble three authentic fixture editions through the production assembler.
    #@param self AuditTest Owner of this independent test's fixture.
    #@return None No value; stores assembled archive paths on self.
    #@effect Writes disposable ZIPs and registers fixture cleanup with unittest.
    def setUp(self):
        self.fixture = FIXTURES.EditionTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        FIXTURES.editions.assemble(self.fixture.args)
        self.pairs = []
        for edition in ("clean", "std", "full"):
            stem = "yaca-fixture-win32-x86-" + edition
            self.pairs.append((self.fixture.args.output / (stem + ".zip"),
                               self.fixture.args.output / (stem + "-notices.zip")))

    # Replace selected ZIP entries while preserving the original members' modes.
    #@param self AuditTest Fixture owner.
    #@param path Path ZIP inside this test's disposable directory.
    #@param changes dict[str,bytes|None] Replacement/addition bytes; None removes a member.
    #@return None No value; rewrites only the selected temporary archive.
    #@effect Reads small fixture payloads and replaces the temporary ZIP file.
    def rewrite(self, path, changes):
        with zipfile.ZipFile(path) as archive:
            items = [(item, archive.read(item)) for item in archive.infolist()]
        seen = set()
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            for item, content in items:
                seen.add(item.filename)
                value = changes.get(item.filename, content)
                if value is not None:
                    archive.writestr(item, value)
            for name, content in changes.items():
                if name not in seen and content is not None:
                    info = zipfile.ZipInfo(name)
                    info.external_attr = (stat.S_IFREG | 0o644) << 16
                    archive.writestr(info, content)

    # Read one pair's companion edition metadata for a negative evidence case.
    #@param self AuditTest Fixture owner.
    #@param index int Pair index: clean=0, std=1, full=2.
    #@return dict Independent JSON edition metadata.
    def metadata(self, index):
        with zipfile.ZipFile(self.pairs[index][1]) as archive:
            return json.loads(archive.read("edition.json"))

    # Update companion metadata and its derived SBOM after a deliberate fixture mutation.
    #@param self AuditTest Fixture owner.
    #@param index int Pair index selected for mutation.
    #@param summary dict New companion metadata; source payloads remain caller-controlled.
    #@return None No value; replaces edition.json and SBOM.spdx.json in the fixture.
    #@effect Writes only the selected temporary companion ZIP.
    def write_metadata(self, index, summary):
        self.rewrite(self.pairs[index][1], {
            "edition.json": json.dumps(summary).encode(),
            "SBOM.spdx.json": json.dumps(FIXTURES.editions.edition_sbom(summary)).encode(),
        })

    # Accept the assembler's exact payloads while exposing absent build evidence.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify all three inventories and the six missing matrix seats.
    def test_assembler_pairs_pass_integrity_without_qualifying_missing_evidence(self):
        pairs = [AUDIT.audit_pair(*pair) for pair in self.pairs]
        self.assertEqual([pair["tools"] for pair in pairs], [0, 4, 10])
        self.assertTrue(all(pair["qualification"] == "pending" for pair in pairs))
        self.assertIn("core-full-test-summary", pairs[0]["core_evidence"]["missing"])
        report = AUDIT.aggregate(pairs)
        self.assertEqual(len(report["missing_pairs"]), 6)
        self.assertFalse(report["evidence_complete"])
        self.assertFalse(report["release_authorized"])

    # Detect a modified tool even after the outer ZIP checksum has been rebound.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require failure at the inner file digest check.
    def test_modified_runtime_file_cannot_hide_behind_an_updated_zip_hash(self):
        summary = self.metadata(1)
        name = summary["tools"][0]["entry_points"][0]
        self.rewrite(self.pairs[1][0], {name: b"changed tool"})
        summary["archive_sha256"] = FIXTURES.editions.digest(self.pairs[1][0])
        self.write_metadata(1, summary)
        with self.assertRaisesRegex(ValueError, "runtime file SHA-256 differs"):
            AUDIT.audit_pair(*self.pairs[1])

    # Reject both undeclared payloads and forged metadata declaring extra root files.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require inventory and runtime-surface failures respectively.
    def test_extra_root_payload_is_rejected_even_when_declared_and_hashed(self):
        summary = self.metadata(0)
        self.rewrite(self.pairs[0][0], {"config.ini": b"private config"})
        summary["archive_sha256"] = FIXTURES.editions.digest(self.pairs[0][0])
        self.write_metadata(0, summary)
        with self.assertRaisesRegex(ValueError, "runtime member inventory differs"):
            AUDIT.audit_pair(*self.pairs[0])
        summary["files"].append({"destination": "config.ini", "executable": False,
                                 "sha256": hashlib.sha256(b"private config").hexdigest()})
        self.write_metadata(0, summary)
        with self.assertRaisesRegex(ValueError, "unexpected runtime surface"):
            AUDIT.audit_pair(*self.pairs[0])

    # Reject unsafe or colliding archive members before using their metadata.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify traversal, case collisions and file/directory conflicts.
    def test_unsafe_member_paths_and_collisions_are_rejected(self):
        path = self.fixture.root / "unsafe.zip"
        for name in ("../escape", "tools/NUL.txt", "tools/a:stream", "yaca.exe", "YACA.EXE", "yaca.exe/child"):
            with self.subTest(name=name):
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("yaca.exe", b"core")
                    if name == "yaca.exe":
                        archive.writestr("tools/a", b"first")
                        archive.writestr("tools/A", b"second")
                    else:
                        archive.writestr(name, b"unexpected")
                with zipfile.ZipFile(path) as archive:
                    with self.assertRaises(ValueError):
                        AUDIT.inventory(archive)

    # Audit both Linux-distinct header names while retaining case-insensitive rejection for Windows.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify target-aware inventory hashes every case-distinct member independently.
    def test_linux_header_case_is_preserved_in_inventory(self):
        path=self.fixture.root/'linux-headers.zip'
        with zipfile.ZipFile(path,'w') as archive:
            archive.writestr('tools/compiler/xt_CONNMARK.h',b'upper header')
            archive.writestr('tools/compiler/xt_connmark.h',b'lower header')
        with zipfile.ZipFile(path) as archive:
            members=AUDIT.inventory(archive,case_sensitive=True)
            self.assertEqual(len(members),2)
            self.assertNotEqual(members['tools/compiler/xt_CONNMARK.h']['sha256'],
                                members['tools/compiler/xt_connmark.h']['sha256'])
            with self.assertRaises(ValueError):
                AUDIT.inventory(archive)

    # Reject a symbolic link member instead of treating its target as payload bytes.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require rejection of Unix symlink ZIP attributes.
    def test_symlink_members_are_rejected(self):
        path = self.fixture.root / "linked.zip"
        with zipfile.ZipFile(path, "w") as archive:
            info = zipfile.ZipInfo("yaca.exe")
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, "../outside")
        with zipfile.ZipFile(path) as archive:
            with self.assertRaisesRegex(ValueError, "regular file"):
                AUDIT.inventory(archive)

    # Detect altered corresponding sources even when runtime bytes stay unchanged.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require the tool source archive digest to match its metadata.
    def test_corresponding_source_bytes_are_verified(self):
        source = self.metadata(1)["tools"][0]["source_archive"]["destination"]
        self.rewrite(self.pairs[1][1], {source: b"wrong source"})
        with self.assertRaisesRegex(ValueError, "tool source SHA-256 differs"):
            AUDIT.audit_pair(*self.pairs[1])

    # Reject wrong catalog pins, tool versions and unauthorized qualification claims.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify each independently forged metadata field.
    def test_catalog_version_and_qualification_claims_are_checked(self):
        original = self.metadata(1)
        for field, value, diagnostic in (("catalog_sha256", "0" * 64, "catalog SHA-256"),
                                         ("release_authorized", True, "unqualified candidates")):
            with self.subTest(field=field):
                summary = copy.deepcopy(original)
                summary[field] = value
                self.write_metadata(1, summary)
                with self.assertRaisesRegex(ValueError, diagnostic):
                    AUDIT.audit_pair(*self.pairs[1])
        summary = copy.deepcopy(original)
        summary["tools"][0]["version"] = "2.7.17"
        self.write_metadata(1, summary)
        with self.assertRaisesRegex(ValueError, "tool version differs"):
            AUDIT.audit_pair(*self.pairs[1])

    # Reject an SPDX file that no longer describes the verified edition bytes.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require agreement between edition metadata and SPDX.
    def test_sbom_cannot_disagree_with_verified_inventory(self):
        self.rewrite(self.pairs[0][1], {"SBOM.spdx.json": b"{}"})
        with self.assertRaisesRegex(ValueError, "SBOM differs"):
            AUDIT.audit_pair(*self.pairs[0])

    # Prevent ambiguous repeated JSON fields from hiding an earlier authorization.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require duplicate-key rejection during evidence parsing.
    def test_duplicate_json_evidence_keys_are_rejected(self):
        text = json.dumps(self.metadata(0))
        text = text[:-1] + ', "release_authorized": true}'
        self.rewrite(self.pairs[0][1], {"edition.json": text.encode()})
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            AUDIT.audit_pair(*self.pairs[0])

    # Record present core evidence and reject a build summary bound to another binary.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify source/test extraction and exact build-core binding.
    def test_core_build_evidence_remains_bound_to_the_packaged_binary(self):
        summary = self.metadata(0)
        build = {"target": "win32-x86", "status": "cross-build-passed", "base_revision": "a" * 40,
                 "source_snapshot_sha256": "b" * 64, "full_tests": "2/2",
                 "artifacts": [{"path": "package/yaca.exe", "sha256": summary["core_sha256"]}]}
        dependencies = {"spdxVersion": "SPDX-2.3", "packages": [
            {"name": name, "checksums": [{"algorithm": "SHA256", "checksumValue": "b" * 64}]}
            for name in ("yaca", "luainstaller", "Lua", "LuaExpat", "Expat", "curl", "MbedTLS", "Mozilla-CA")]}
        self.rewrite(self.pairs[0][1], {"core/docs/build-summary.json": json.dumps(build).encode(),
                                       "core/docs/COMPONENTS.txt": b"fixture components",
                                       "core/docs/SBOM.spdx.json": json.dumps(dependencies).encode()})
        report = AUDIT.audit_pair(*self.pairs[0])
        self.assertEqual(report["core_evidence"]["full_tests"], "2/2")
        self.assertEqual(report["core_evidence"]["missing"], [])
        build["artifacts"][0]["sha256"] = "0" * 64
        self.rewrite(self.pairs[0][1], {"core/docs/build-summary.json": json.dumps(build).encode()})
        with self.assertRaisesRegex(ValueError, "build summary core differs"):
            AUDIT.audit_pair(*self.pairs[0])

    # Reject duplicate seats, mixed cores and mixed product versions in a matrix.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify aggregate checks independently of ZIP verification.
    def test_matrix_rejects_duplicate_seats_mixed_cores_and_versions(self):
        first, second = [AUDIT.audit_pair(*pair) for pair in self.pairs[:2]]
        with self.assertRaisesRegex(ValueError, "duplicate target/edition"):
            AUDIT.aggregate([first, first])
        second["core_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "edition cores differ"):
            AUDIT.aggregate([first, second])
        second["core_sha256"] = first["core_sha256"]
        second["version"] = "other"
        with self.assertRaisesRegex(ValueError, "versions differ"):
            AUDIT.aggregate([first, second])

    # Ensure strict CLI matrix requirements fail while preserving a reviewable report.
    #@param self AuditTest Fixture owner.
    #@return None Assertions verify a missing matrix cannot exit successfully.
    #@effect Starts the build-host audit CLI against disposable fixture ZIPs.
    def test_strict_cli_records_incomplete_matrix_and_exits_nonzero(self):
        output = self.fixture.root / "audit.json"
        result = subprocess.run([sys.executable, str(ROOT / ".tools/qualification/audit_editions.py"),
                                 "--pair", *(str(path) for path in self.pairs[0]),
                                 "--output", str(output), "--require-nine"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matrix incomplete", result.stderr)
        self.assertEqual(len(json.loads(output.read_text())["missing_pairs"]), 8)

    # Detect incomplete Git transport payloads independently of a matching version label.
    #@param self AuditTest Fixture owner.
    #@return None Assertions require both missing HTTP helper names in the full report.
    def test_git_transport_closure_is_not_inferred_from_its_version(self):
        report = AUDIT.audit_pair(*self.pairs[2])
        self.assertEqual(report["tool_payload_gaps"], ["git-remote-http", "git-remote-https"])


if __name__ == "__main__":
    unittest.main()
