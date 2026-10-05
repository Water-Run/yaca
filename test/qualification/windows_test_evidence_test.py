#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: windows_test_evidence_test.py
# Description: Reject mismatched or incomplete target-suite evidence before it enters Windows candidate notices.

import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT=pathlib.Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('attach_windows_tests',ROOT/'.tools/qualification/attach_windows_test_summary.py')
ATTACH=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ATTACH)


#@class WindowsEvidenceTest Owns disposable synthetic candidate files; no fixture constitutes real target qualification.
#@field root Path Temporary build/evidence parent removed after each case.
#@field receipt dict Mutable fixture receipt for deliberate binding and outcome faults.
class WindowsEvidenceTest(unittest.TestCase):
    # Create a synthetic captured core, source snapshot, raw log and matching successful receipt.
    #@param self WindowsEvidenceTest Fixture owner.
    #@return None No result; stores fixture paths and metadata on self.
    #@effect Creates only the disposable temporary directory and its fixture files.
    def setUp(self):
        temporary=tempfile.TemporaryDirectory(prefix='windows evidence ')
        self.addCleanup(temporary.cleanup)
        self.root=pathlib.Path(temporary.name)
        (self.root/'package').mkdir()
        (self.root/'companion/docs').mkdir(parents=True)
        (self.root/'package/yaca.exe').write_bytes(b'synthetic candidate core')
        (self.root/'yaca-source.tar.gz').write_bytes(b'synthetic captured source')
        self.log=self.root/'raw-test.log'
        self.log.write_bytes(b'PASS fixture-only\nSUMMARY total=9 passed=9 failed=0\r\n')
        core=ATTACH.digest(self.root/'package/yaca.exe')
        source=ATTACH.digest(self.root/'yaca-source.tar.gz')
        self.summary={'target':'win32-x86','release_authorized':False,'target_qualification_complete':False,
                      'source_snapshot_sha256':source,'artifacts':[{'path':'package/yaca.exe','sha256':core}]}
        self.receipt={'schema':'yaca-target-full-test-v1','status':'PASS','target':'win32-x86',
                      'exit_code':0,'core_sha256':core,'source_archive_sha256':source,
                      'log_sha256':ATTACH.digest(self.log),'total':9,'passed':9,'failed':0,
                      'command':'yaca.exe --lua -E source/test/run.lua','environment':'synthetic fixture only'}

    # Invoke the real collector with explicit fixture paths and captured stdout.
    #@param self WindowsEvidenceTest Fixture owner whose receipt/summary may contain an injected fault.
    #@return None No result; collector failures propagate to the assertion.
    #@effect Writes fixture inputs, temporarily replaces argv, and lets the collector update only the owned candidate.
    def attach(self):
        receipt_path=self.root/'receipt.json'
        receipt_path.write_text(json.dumps(self.receipt))
        (self.root/'companion/docs/build-summary.json').write_text(json.dumps(self.summary))
        with mock.patch('sys.argv',['attach_windows_test_summary.py',str(self.root),str(receipt_path),str(self.log)]), \
                contextlib.redirect_stdout(io.StringIO()):
            ATTACH.main()

    # Preserve actual raw log bytes and bind the accepted count to the core build summary.
    #@param self WindowsEvidenceTest Fixture owner.
    #@return None Assertions check exact log bytes and core/source/count bindings.
    def test_matching_receipt_attaches_actual_log(self):
        self.attach()
        docs=self.root/'companion/docs'
        summary=json.loads((docs/'build-summary.json').read_text())
        self.assertEqual(summary['full_tests'],'9/9')
        self.assertEqual(summary['full_test_evidence']['core_sha256'],self.receipt['core_sha256'])
        self.assertEqual((docs/'full-test-target.log').read_bytes(),self.log.read_bytes())

    # Stop before copying evidence when its target, core, source or log differs from the build inputs.
    #@param self WindowsEvidenceTest Fixture owner.
    #@return None Assertions require every cross-target or changed-byte receipt to fail without an attached log.
    def test_other_target_or_bytes_do_not_attach(self):
        original=dict(self.receipt)
        for key,value in (('target','win64-x86_64'),('core_sha256','0'*64),
                          ('source_archive_sha256','0'*64),('log_sha256','0'*64)):
            self.receipt=dict(original)
            self.receipt[key]=value
            with self.subTest(field=key),self.assertRaises(ValueError):
                self.attach()
            self.assertFalse((self.root/'companion/docs/full-test-target.log').exists())

    # Refuse a failed process, Boolean exit code, inconsistent count or partial-suite command.
    #@param self WindowsEvidenceTest Fixture owner.
    #@return None Assertions reject incomplete or falsely successful outcomes before notices change.
    def test_failed_and_partial_suites_are_refused(self):
        original=dict(self.receipt)
        for key,value in (('exit_code',1),('exit_code',False),('passed',8),
                          ('command','yaca.exe --lua -E source/test/unit/compact_test.lua')):
            self.receipt=dict(original)
            self.receipt[key]=value
            with self.subTest(field=key,value=value),self.assertRaises(ValueError):
                self.attach()
            self.assertFalse((self.root/'companion/docs/full-test-target.log').exists())


if __name__=='__main__':
    unittest.main()
