#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-11
# File: portable_upgrade_test.py
# Description: Verifies retained-data upgrade evidence rejects no-op, link and altered-data cases while preserving private bytes on successful replacement.

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('portable_upgrade', ROOT / '.tools/qualification/portable_upgrade.py')
UPGRADE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPGRADE)


#@class UpgradeTest Exercises real temporary files and the maintained replacement routine without launching applications.
class UpgradeTest(unittest.TestCase):
    # Prepare a stopped-core layout with representative private configuration and binary workspace data.
    #@param self UpgradeTest Test owner.
    #@param directory str Temporary parent supplied by the test case.
    #@return tuple Application root, replacement core and absent public receipt paths.
    #@effect Creates only files below the case's temporary directory.
    def fixture(self, directory):
        parent = Path(directory)
        root = parent / 'application'
        (root / '__yaca__/CONTEXT').mkdir(parents=True)
        (root / 'workspace/empty').mkdir(parents=True)
        (root / 'yaca').write_bytes(b'old executable')
        (root / 'yaca').chmod(0o755)
        (root / '__yaca__/config.ini').write_bytes(b'private configuration\x00')
        (root / '__yaca__/CONTEXT/session.xml').write_bytes(b'<context>persisted</context>')
        (root / 'workspace/user.bin').write_bytes(b'\x00\xffretained\r\n')
        replacement = parent / 'new-core'
        replacement.write_bytes(b'new executable')
        return root, replacement, parent / 'receipt.json'

    # Require a real core change while preserving every data entry and executable mode.
    #@param self UpgradeTest Test owner.
    #@return None Assertions require different core digests and identical data inventory.
    def test_preserves_all_owned_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root, replacement, receipt = self.fixture(directory)
            before = UPGRADE.inventory(root)
            result = UPGRADE.replace_core(root, replacement, receipt)
            self.assertEqual(UPGRADE.inventory(root), before)
            self.assertEqual((root / 'yaca').read_bytes(), b'new executable')
            self.assertNotEqual(result['old_core_sha256'], result['new_core_sha256'])
            self.assertTrue(result['all_data_bytes_preserved'])
            self.assertFalse((root / 'yaca.upgrade-partial').exists())

    # Refuse an existing receipt or identical core before replacing any executable.
    #@param self UpgradeTest Test owner.
    #@return None Assertions require refusal and the original executable bytes.
    def test_refuses_ambiguous_or_noop_upgrade(self):
        with tempfile.TemporaryDirectory() as directory:
            root, replacement, receipt = self.fixture(directory)
            receipt.write_text('existing')
            with self.assertRaises(ValueError):
                UPGRADE.replace_core(root, replacement, receipt)
            replacement.write_bytes((root / 'yaca').read_bytes())
            with self.assertRaises(ValueError):
                UPGRADE.replace_core(root, replacement, receipt.with_name('other.json'))
            self.assertEqual((root / 'yaca').read_bytes(), b'old executable')

    # Reject a workspace link before copying the replacement core or reading data outside the owned tree.
    #@param self UpgradeTest Test owner.
    #@return None Assertions require refusal, original core bytes and no receipt.
    def test_rejects_linked_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root, replacement, receipt = self.fixture(directory)
            outside = Path(directory) / 'outside-data'
            outside.write_bytes(b'external')
            (root / 'workspace/linked').symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'symbolic link'):
                UPGRADE.replace_core(root, replacement, receipt)
            self.assertEqual((root / 'yaca').read_bytes(), b'old executable')
            self.assertFalse(receipt.exists())

    # Detect an actual data mutation injected during copying instead of accepting a successful file copy alone.
    #@param self UpgradeTest Test owner.
    #@return None Assertions require a failed preservation check and no PASS receipt.
    def test_detects_altered_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root, replacement, receipt = self.fixture(directory)
            original = UPGRADE.shutil.copyfileobj
            # Copy the core normally, then corrupt one owned data file to test the independent inventory comparison.
            #@param source file Open replacement core stream.
            #@param destination file Open isolated temporary core output.
            #@param length int Copy block bound.
            #@return None No value; intentionally changes only the fixture configuration.
            def corrupt(source, destination, length):
                original(source, destination, length)
                (root / '__yaca__/config.ini').write_bytes(b'changed')
            with mock.patch.object(UPGRADE.shutil, 'copyfileobj', corrupt):
                with self.assertRaisesRegex(ValueError, 'altered preserved data'):
                    UPGRADE.replace_core(root, replacement, receipt)
            self.assertFalse(receipt.exists())


if __name__ == '__main__':
    unittest.main()
