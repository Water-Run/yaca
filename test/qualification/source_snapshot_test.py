#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: source_snapshot_test.py
# Description: Verify working-tree archive bytes, ignored-credential exclusion and refusal of unsafe or occupied outputs.

import importlib.util
import json
import os
import pathlib
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT=pathlib.Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('source_snapshot',ROOT/'.tools/qualification/source_snapshot.py')
SNAPSHOT=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SNAPSHOT)


#@class SnapshotTest Owns a disposable Git repository and source archive fixture.
#@field root Path Temporary repository, removed by the registered fixture cleanup.
#@field output Path Initially absent archive directory outside the fixture repository.
class SnapshotTest(unittest.TestCase):
    # Initialize a local-only repository and a committed source file.
    #@param self SnapshotTest Fixture owner.
    #@return None No value; paths and Git environment are stored on self.
    #@effect Creates disposable source files and local Git metadata without global configuration changes.
    def setUp(self):
        temporary=tempfile.TemporaryDirectory(prefix='source snapshot ')
        self.addCleanup(temporary.cleanup)
        self.root=pathlib.Path(temporary.name)/'repo'
        self.root.mkdir()
        self.output=self.root.parent/'snapshot'
        self.environment=dict(os.environ,GIT_CONFIG_GLOBAL=os.devnull,GIT_CONFIG_NOSYSTEM='1')
        self.git(['init','-q'])
        self.git(['config','user.name','Snapshot Fixture'])
        self.git(['config','user.email','fixture@example.invalid'])
        (self.root/'tracked.txt').write_text('before\n')
        (self.root/'.gitignore').write_text('private/\n')
        self.git(['add','tracked.txt','.gitignore'])
        self.git(['commit','-qm','fixture baseline'])

    # Execute one literal Git command inside the disposable fixture repository.
    #@param self SnapshotTest Fixture owner.
    #@param arguments list[str] Literal Git arguments in their original order.
    #@return None No value; Git failure raises CalledProcessError.
    #@effect Changes only test-local repository metadata; captures command output.
    def git(self,arguments):
        subprocess.run(['git',*arguments],cwd=self.root,env=self.environment,
                       capture_output=True,check=True)

    # Snapshot pending tracked and new sources without an ignored credential fixture.
    #@param self SnapshotTest Fixture owner.
    #@return None Assertions verify exact source bytes and the archive digest manifest.
    #@effect Modifies temporary sources and creates the test-owned archive directory.
    def test_pending_sources_are_archived_and_ignored_credentials_are_excluded(self):
        (self.root/'tracked.txt').write_text('after\n')
        (self.root/'new.txt').write_text('new\n')
        (self.root/'private').mkdir()
        (self.root/'private/config.ini').write_text('fixture-secret\n')
        manifest=SNAPSHOT.snapshot(self.root,self.output)
        self.assertTrue(manifest['dirty'])
        self.assertEqual(manifest['source_scope'],'working-tree')
        self.assertEqual(manifest['archive_sha256'],SNAPSHOT.digest(self.output/'yaca-source.tar.gz'))
        with tarfile.open(self.output/'yaca-source.tar.gz') as archive:
            self.assertEqual(set(archive.getnames()),{'.gitignore','new.txt','tracked.txt'})
            self.assertEqual(archive.extractfile('tracked.txt').read(),b'after\n')
            self.assertEqual(archive.extractfile('new.txt').read(),b'new\n')
        self.assertEqual(json.loads((self.output/'snapshot.json').read_text()),manifest)

    # Refuse a maintained symlink instead of copying its external target bytes.
    #@param self SnapshotTest Fixture owner.
    #@return None Assertions verify symlink rejection leaves no output directory.
    #@effect Creates a test-owned link to a fixture file outside the repository.
    def test_symlink_source_cannot_read_an_external_file(self):
        external=self.root.parent/'external.txt'
        external.write_text('outside\n')
        (self.root/'linked.txt').symlink_to(external)
        with self.assertRaisesRegex(ValueError,'regular'):
            SNAPSHOT.snapshot(self.root,self.output)
        self.assertFalse(self.output.exists())

    # Preserve existing output directories and refuse maintained private-data roots.
    #@param self SnapshotTest Fixture owner.
    #@return None Assertions verify occupied-output and private-data refusal.
    #@effect Creates only fixture-owned sentinels and a deliberately unignored data directory.
    def test_existing_outputs_and_private_data_roots_are_refused(self):
        self.output.mkdir()
        (self.output/'keep.txt').write_text('keep\n')
        with self.assertRaisesRegex(ValueError,'already exists'):
            SNAPSHOT.snapshot(self.root,self.output)
        self.assertEqual((self.output/'keep.txt').read_text(),'keep\n')
        (self.root/'__yaca__').mkdir()
        (self.root/'__yaca__/config.ini').write_text('fixture-private\n')
        with self.assertRaisesRegex(ValueError,'private data'):
            SNAPSHOT.snapshot(self.root,self.root.parent/'other-output')

    # Bind identical maintained bytes to the same archive across independent platform build times.
    #@param self SnapshotTest Fixture owner.
    #@return None Assertions require byte-identical source archives despite a different wall clock.
    #@effect Creates two separate disposable snapshot outputs without modifying the repository.
    def test_platform_snapshots_are_independent_of_archive_wall_clock(self):
        with mock.patch('time.time',return_value=1791158400):
            first=SNAPSHOT.snapshot(self.root,self.output)
        second_output=self.root.parent/'second-snapshot'
        with mock.patch('time.time',return_value=1791162000):
            second=SNAPSHOT.snapshot(self.root,second_output)
        self.assertEqual(first['archive_sha256'],second['archive_sha256'])
        self.assertEqual((self.output/'yaca-source.tar.gz').read_bytes(),
                         (second_output/'yaca-source.tar.gz').read_bytes())


if __name__=='__main__':
    unittest.main()
