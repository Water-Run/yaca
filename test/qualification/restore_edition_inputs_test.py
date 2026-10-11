#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-11
# File: restore_edition_inputs_test.py
# Description: Exercise byte-bound toolbox recovery, old-core exclusion, new-core reassembly and rejection of incorrect or damaged edition pairs.

import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('restore_edition_inputs', ROOT / '.tools/qualification/restore_edition_inputs.py')
RESTORE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESTORE)
SPEC = importlib.util.spec_from_file_location('recovery_edition_fixtures', ROOT / 'test/release/editions_test.py')
FIXTURES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURES)


#@class RecoveryTest Disposable production-assembler fixtures for the recovery boundary.
#@field fixture EditionTest Owns tiny core/tool/source inputs and temporary cleanup.
#@field runtime Path Full fixture runtime ZIP with genuine assembler metadata.
#@field notices Path Matching full notices ZIP with source archives.
class RecoveryTest(unittest.TestCase):
    # Assemble a real full fixture pair before each independent recovery scenario.
    #@param self RecoveryTest Test instance owning this disposable fixture.
    #@return None No result; registers cleanup and stores the full pair paths.
    #@effect Creates tiny authentic ZIPs through the production assembler.
    def setUp(self):
        self.fixture = FIXTURES.EditionTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        for tool in self.fixture.inputs['tools']:
            if tool['id'] == 'git':
                for helper in ('git-remote-http', 'git-remote-https'):
                    tool['files'].append(self.fixture.file(
                        helper + '.exe', 'tools/git/' + helper + '.exe', b'fixture HTTP helper'))
        self.fixture.save()
        FIXTURES.editions.assemble(self.fixture.args)
        stem = self.fixture.args.output / 'yaca-fixture-win32-x86-full'
        self.runtime = Path(str(stem) + '.zip')
        self.notices = Path(str(stem) + '-notices.zip')

    # Prove recovered tools can assemble a different core while preserving corresponding source identities.
    #@param self RecoveryTest Fixture owner.
    #@return None No value; assertions require unchanged source hashes, an excluded old core and an accepted replacement core.
    #@effect Recovers and reassembles disposable inputs; no recovered programs execute.
    def test_recovery_reassembles_new_core_without_old_core_evidence(self):
        output = self.fixture.root / 'recovered'
        receipt = RESTORE.restore(self.runtime, self.notices, 'win32-x86', output)
        self.assertEqual(len(receipt['tools']), 10)
        self.assertFalse((output / 'yaca.exe').exists())
        self.assertFalse((output / 'core').exists())
        self.assertFalse(receipt['old_core_adopted'])
        inputs = json.loads((output / 'tool-inputs.json').read_text())
        for expected, actual in zip(self.fixture.inputs['tools'], inputs['tools']):
            self.assertEqual(actual['id'], expected['id'])
            self.assertEqual(actual['source_archive']['sha256'], expected['source_archive']['sha256'])
        replacement = self.fixture.root / 'replacement.exe'
        replacement.write_bytes(self.fixture.args.core.read_bytes() + b'replacement-core')
        self.fixture.args.core = replacement
        self.fixture.args.core_sha256 = FIXTURES.editions.digest(replacement)
        self.fixture.args.tool_inputs = output / 'tool-inputs.json'
        self.fixture.args.output = self.fixture.root / 'reassembled'
        results = FIXTURES.editions.assemble(self.fixture.args)
        self.assertTrue(all(item['core_sha256'] == self.fixture.args.core_sha256 for item in results))

    # Reject a mismatched target before creating any recovery output.
    #@param self RecoveryTest Fixture owner.
    #@return None No value; assertions require failure and an absent output tree.
    #@effect Reads the fixture pair without writing an accepted staging directory.
    def test_other_target_is_rejected(self):
        output = self.fixture.root / 'wrong-target'
        with self.assertRaisesRegex(ValueError, 'another target'):
            RESTORE.restore(self.runtime, self.notices, 'win64-x86_64', output)
        self.assertFalse(output.exists())

    # Reject changed runtime bytes instead of importing them under the companion's original digest.
    #@param self RecoveryTest Fixture owner.
    #@return None No value; assertions require damaged-pair rejection and no accepted recovery tree.
    #@effect Alters only the disposable runtime ZIP's trailing bytes before attempting recovery.
    def test_changed_archive_is_rejected(self):
        with self.runtime.open('ab') as target:
            target.write(b'changed-runtime')
        output = self.fixture.root / 'damaged'
        with self.assertRaisesRegex(ValueError, 'SHA-256 differs'):
            RESTORE.restore(self.runtime, self.notices, 'win32-x86', output)
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
