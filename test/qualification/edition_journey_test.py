#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: edition_journey_test.py
# Description: Verify real PTY execution and failure/consent boundaries of the offline edition journey driver.

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".tools/qualification"))
SPEC = importlib.util.spec_from_file_location("edition_journey", ROOT / ".tools/qualification/edition_journey.py")
JOURNEY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(JOURNEY)


#@class JourneyTest Process/TTY and unsupported-action boundary tests without provider requests.
#@field temporary TemporaryDirectory Test-owned scratch root and cleanup lifetime.
#@field root Path Isolated scratch path used for driver and command execution.
class JourneyTest(unittest.TestCase):
    # Allocate an independent scratch tree with a sentinel owned by the caller.
    #@param self JourneyTest Owner of the test fixture.
    #@return None No value; records scratch paths and registers their cleanup.
    #@effect Writes a temporary sentinel to detect unauthorized scratch cleanup.
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="journey fixture ")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "keep.txt").write_text("caller-owned\n")

    # Verify the command runner creates a controlling terminal for all standard streams.
    #@param self JourneyTest Fixture owner.
    #@return None Assertions require a reaped successful child reporting three TTY streams.
    #@effect Starts an isolated interpreter under the production PTY runner.
    def test_real_pty_connects_all_standard_streams(self):
        result = JOURNEY.run_command([sys.executable, "-c",
                                      "import os; print(os.isatty(0), os.isatty(1), os.isatty(2))"],
                                     self.root, terminal=True)
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["output"].strip(), "True True True")

    # Preserve the failed exit code of a process that prints a success-like token.
    #@param self JourneyTest Fixture owner.
    #@return None Assertions require exit 7 even though the transcript contains 42.
    #@effect Executes a small failing child under the production PTY runner.
    def test_pty_failure_exit_is_preserved(self):
        result = JOURNEY.run_command([sys.executable, "-c", "import sys; print(42); sys.exit(7)"],
                                     self.root, terminal=True)
        self.assertEqual(result["exit_code"], 7)
        self.assertEqual(result["output"].strip(), "42")

    # Reject failed, incomplete or online transcripts masquerading as offline partial success.
    #@param self JourneyTest Fixture owner.
    #@return None Assertions verify exact stage, request, exit and failure-field checks.
    def test_partial_stage1_accepts_warnings_and_rejects_contradictions(self):
        text = "ST1-CONFIG-SOURCE WARNING uninitialized\nself-test outcome=partial completed-stage=1 online-requests=0 auto-fixes=0"
        self.assertTrue(JOURNEY.stage1_passed({"output": text, "exit_code": 1}))
        for output, code in (("ST1-DATA-ROOT FAILED unavailable\n" + text, 1),
                             (text.replace("stage=1", "stage=0"), 1),
                             (text.replace("requests=0", "requests=1"), 1),
                             (text.replace("fixes=0", "fixes=2"), 1), (text, 0)):
            with self.subTest(output=output, code=code):
                self.assertFalse(JOURNEY.stage1_passed({"output": output, "exit_code": code}))

    # Refuse unimplemented online steps before opening a package or modifying scratch.
    #@param self JourneyTest Fixture owner.
    #@return None Assertions require nonzero CLI status and the intact caller-owned sentinel.
    #@effect Starts the driver CLI with absent archives and an explicit online option.
    def test_online_request_is_refused_before_effects(self):
        result = subprocess.run([sys.executable, str(ROOT / ".tools/qualification/edition_journey.py"),
                                 str(ROOT), str(self.root / "absent.zip"), "linux-x86_64", str(self.root),
                                 "--i-accept-online-journey", str(self.root / "private.ini")],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("online steps are not executed", result.stderr)
        self.assertEqual(list(self.root.iterdir()), [self.root / "keep.txt"])

    # Reject cross-platform runtime execution instead of reporting skipped steps as success.
    #@param self JourneyTest Fixture owner.
    #@return None Assertions require refusal before scratch or package effects.
    #@effect Starts the Linux driver CLI with a Windows target and absent archive.
    def test_host_mismatch_is_refused_before_effects(self):
        result = subprocess.run([sys.executable, str(ROOT / ".tools/qualification/edition_journey.py"),
                                 str(ROOT), str(self.root / "absent.zip"), "win32-x86", str(self.root)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("target does not match", result.stderr)
        self.assertEqual((self.root / "keep.txt").read_text(), "caller-owned\n")

    # Keep linked archive paths visible to the audit instead of resolving them away.
    #@param self JourneyTest Fixture owner.
    #@return None Assertions require symlink refusal before extraction or scratch allocation.
    #@effect Writes a disposable link and invokes the CLI with an otherwise absent companion.
    def test_linked_archive_is_rejected_before_scratch_effects(self):
        source = self.root / "source.zip"
        source.write_bytes(b"not a ZIP")
        linked = self.root / "linked.zip"
        linked.symlink_to(source)
        original = set(self.root.iterdir())
        result = subprocess.run([sys.executable, str(ROOT / ".tools/qualification/edition_journey.py"),
                                 str(ROOT), str(linked), "linux-x86_64", str(self.root)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink inputs are not allowed", result.stderr)
        self.assertEqual(set(self.root.iterdir()), original)


if __name__ == "__main__":
    unittest.main()
