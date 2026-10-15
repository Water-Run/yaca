#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-15
# File: corresponding_sources_test.py
# Description: Reject binary-only toolbox provenance and verify corresponding-source profile membership, digests and safe archive paths.

import hashlib
import importlib.util
import io
import json
import subprocess
import sys
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('corresponding_sources', ROOT / '.tools/qualification/audit_corresponding_sources.py')
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)
SPEC = importlib.util.spec_from_file_location('bundle_sources', ROOT / '.tools/qualification/bundle_corresponding_sources.py')
BUNDLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUNDLE)


#@class SourceAuditTest Small disposable source archives exercising actual structural failures.
#@field temporary TemporaryDirectory Owns the isolated archive root and automatic cleanup.
#@field root Path Absolute disposable directory used by every scenario.
class SourceAuditTest(unittest.TestCase):
    # Create one independent disposable source-archive directory.
    #@param self SourceAuditTest Owner of this test's files and cleanup.
    #@return None No value; stores the temporary root.
    #@effect Creates a uniquely named directory and registers its cleanup.
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='yaca-source-audit-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    # Write a tiny real tar without executing any member data.
    #@param self SourceAuditTest Fixture owner.
    #@param files dict[str,bytes] Member names and exact data bytes, including deliberate unsafe test paths.
    #@return Path Newly written fixture archive.
    #@effect Creates only the fixture tar beneath the owned temporary root.
    def archive(self, files):
        path = self.root / 'source.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            for name, content in files.items():
                member = tarfile.TarInfo(name)
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
        return path

    # Require an actual source member's digest and complete membership to verify its declared profile.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require valid profile acknowledgement and rejection after changed source bytes.
    #@effect Writes two tiny source-archive variants in this test's owned directory.
    def test_verified_profile_binds_member_bytes(self):
        source = b'original source data'
        profile = {'schema': 'yaca-corresponding-source-v1',
                   'files': [{'path': 'upstream/source.tar.xz', 'sha256': hashlib.sha256(source).hexdigest()}]}
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'upstream/source.tar.xz': source})
        self.assertTrue(AUDIT.inspect(path)['profile_verified'])
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'upstream/source.tar.xz': b'changed'})
        self.assertFalse(AUDIT.inspect(path)['profile_verified'])
        self.assertIn('source-profile digest differs: upstream/source.tar.xz', AUDIT.inspect(path)['findings'])

    # Reject the executable distributions that were incorrectly attached as Windows Git/compiler source.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require a binary-source finding for both PE and ELF markers.
    #@effect Writes fixture bytes without launching any binary.
    def test_binary_distributions_are_rejected(self):
        for magic in (b'MZ', b'\x7fELF'):
            path = self.root / 'binary'
            path.write_bytes(magic + b'fixture')
            self.assertEqual(AUDIT.inspect(path)['kind'], 'binary-distribution')
            self.assertTrue(AUDIT.inspect(path)['findings'])

    # Reject a compiled distribution even when a forged profile correctly binds its bytes.
    #@param self SourceAuditTest Disposable source archive owner.
    #@return None Assertions require binary-member rejection rather than mere hash consistency.
    #@effect Creates a tiny forged Git source profile without executing its binary member.
    def test_profile_cannot_conceal_compiled_distribution(self):
        compiled = b'MZnot source'
        profile = {'schema': 'yaca-corresponding-source-v1', 'tool': 'git', 'version': '2.46.2',
                   'files': [{'path': 'upstream/PortableGit.exe', 'sha256': hashlib.sha256(compiled).hexdigest()}]}
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'upstream/PortableGit.exe': compiled})
        report = AUDIT.inspect(path)
        self.assertFalse(report['profile_verified'])
        self.assertTrue(any('compiled distribution' in item for item in report['findings']))

    # Bind an explicit Git source profile to its exact bytes and version while preserving partial closure.
    #@param self SourceAuditTest Disposable source fixture owner.
    #@return None Assertions require correct identity, declared partial state and refusal of changed bytes or another tool/version.
    #@effect Creates source-data fixtures and reads them through production admission; no programs run.
    def test_git_source_admission_binds_identity_and_partial_status(self):
        source = b'original upstream source'
        profile = {'schema': 'yaca-corresponding-source-v1', 'tool': 'git', 'version': '2.46.2',
                   'provenance': {'status': 'partial', 'complete_source_closure': False},
                   'files': [{'path': 'upstream/source.tar.xz', 'sha256': hashlib.sha256(source).hexdigest()}]}
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'upstream/source.tar.xz': source})
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        record = AUDIT.admit_git_source(path, expected, '2.46.2')
        self.assertEqual(record['source_closure'], 'partial')
        self.assertEqual(record['sha256'], expected)
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            AUDIT.admit_git_source(path, '0' * 64, '2.46.2')
        with self.assertRaisesRegex(ValueError, 'identity'):
            AUDIT.admit_git_source(path, expected, '2.10.0')
        profile['tool'] = 'compiler'
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'upstream/source.tar.xz': source})
        with self.assertRaisesRegex(ValueError, 'identity'):
            AUDIT.admit_git_source(path, hashlib.sha256(path.read_bytes()).hexdigest(), '2.46.2')

    # Do not convert structural verification into an unreviewed claim of complete Git source closure.
    #@param self SourceAuditTest Disposable source fixture owner.
    #@return None Assertions require pending review unless the byte-bound profile explicitly records full closure and passed manual review.
    #@effect Creates source profiles and checks admission metadata without granting release qualification.
    def test_complete_git_source_claim_requires_explicit_review(self):
        source = b'upstream source'
        profile = {'schema': 'yaca-corresponding-source-v1', 'tool': 'git', 'version': '2.10.0',
                   'provenance': {'status': 'complete', 'complete_source_closure': True},
                   'files': [{'path': 'source.tar.xz', 'sha256': hashlib.sha256(source).hexdigest()}]}
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'source.tar.xz': source})
        record = AUDIT.admit_git_source(path, hashlib.sha256(path.read_bytes()).hexdigest(), '2.10.0')
        self.assertEqual(record['source_closure'], 'pending-review')
        profile['provenance']['manual_source_closure_review'] = 'passed'
        path = self.archive({'source-profile.json': json.dumps(profile).encode(), 'source.tar.xz': source})
        record = AUDIT.admit_git_source(path, hashlib.sha256(path.read_bytes()).hexdigest(), '2.10.0')
        self.assertEqual(record['source_closure'], 'complete')

    # Reject the former Git binary-source fallback in both full stagers before any output tree is created.
    #@param self SourceAuditTest Disposable binary fixture and output owner.
    #@return None Assertions require explicit source rejection and an absent staging output for both targets.
    #@effect Launches only the maintained Python stagers with rejected fixture bytes; no toolbox program runs.
    def test_windows_full_stagers_reject_binary_git_source_before_output(self):
        source = self.root / 'PortableGit.exe'
        source.write_bytes(b'MZfixture installer')
        for target in ('win32', 'win64'):
            output = self.root / target
            command = [sys.executable, str(ROOT / '.tools/qualification' / ('prepare_' + target + '_full.py')),
                       *[str(self.root / name) for name in ('std', 'build', 'python.zip', 'cache')], str(output),
                       '--git-source', str(source), '--git-source-sha256', hashlib.sha256(source.read_bytes()).hexdigest()]
            result = subprocess.run(command, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'Git source', result.stderr)
            self.assertFalse(output.exists())

    # Produce portable metadata paths even when the staging host uses Windows path separators.
    #@param self SourceAuditTest Disposable tiny toolbox tree owner.
    #@return None Assertions require forward-slash destinations from both maintained full collectors.
    #@effect Imports maintained stagers and reads fixture files without running a toolbox program.
    def test_full_collectors_emit_portable_archive_paths(self):
        directory = self.root / 'tools/git/cmd'
        directory.mkdir(parents=True)
        (directory / 'git.exe').write_bytes(b'MZfixture')
        for target in ('win32', 'win64'):
            spec = importlib.util.spec_from_file_location('collector_' + target, ROOT / '.tools/qualification' / ('prepare_' + target + '_full.py'))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            records = module.collect(self.root, 'git')
            self.assertEqual([item['destination'] for item in records], ['tools/git/cmd/git.exe'])
            self.assertNotIn('\\', records[0]['source'])

    # Reject the old Python closure's lone portable ZIP instead of treating packaging as dependency source.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require a binary-only closure finding.
    #@effect Creates one tiny tar containing a nonexecuted binary-archive fixture.
    def test_lone_portable_binary_zip_is_rejected(self):
        path = self.archive({'python38-portable.zip': b'PK fixture'})
        self.assertTrue(AUDIT.inspect(path)['findings'])

    # Refuse unsafe members even when a profile could otherwise conceal them.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require path traversal rejection without extraction.
    #@effect Creates a deliberately unsafe tar only inside the disposable test root.
    def test_unsafe_source_member_is_rejected(self):
        path = self.archive({'../escaped-source': b'fixture'})
        self.assertTrue(AUDIT.inspect(path)['findings'])

    # Verify production bundling and auditing agree on the complete admitted source bytes.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require a verified archive and refusal to replace it.
    #@effect Creates a source-data fixture and one production corresponding-source bundle.
    def test_production_bundle_is_verified_without_replacing_existing_output(self):
        source = self.root / 'upstream.tar.xz'
        source.write_bytes(b'fixture upstream source')
        profile = {'schema': 'yaca-corresponding-source-inputs-v1', 'tool': 'fixture', 'version': '1',
                   'inputs': [{'path': source.name, 'destination': 'upstream/source.tar.xz',
                               'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}]}
        output = self.root / 'bundled.tar.gz'
        BUNDLE.bundle(profile, self.root, output)
        self.assertTrue(AUDIT.inspect(output)['profile_verified'])
        before = output.read_bytes()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            BUNDLE.bundle(profile, self.root, output)
        self.assertEqual(output.read_bytes(), before)

    # Preserve a competing writer's artifact even when it appears immediately before publication.
    #@param self SourceAuditTest Owns the source fixture, competing file and patched publication calls.
    #@return None Assertions require atomic refusal, unchanged competing bytes and temporary-file cleanup.
    #@effect Creates disposable files and intercepts rename/link only while production bundling runs.
    def test_bundle_publication_cannot_replace_a_concurrent_artifact(self):
        source = self.root / 'upstream.txt'
        source.write_bytes(b'original source')
        profile = {'schema': 'yaca-corresponding-source-inputs-v1', 'tool': 'fixture', 'version': '1',
                   'inputs': [{'path': source.name, 'destination': 'upstream/source.txt',
                               'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}]}
        output = self.root / 'competing.tar.gz'
        competing_bytes = b'published by another writer'
        original_rename, original_link = BUNDLE.os.rename, BUNDLE.os.link

        # Insert a competing file at the legacy rename boundary and delegate to the real filesystem.
        #@param staged Path Completed temporary source archive offered for publication.
        #@param destination Path Output path that another writer occupies before the rename syscall.
        #@return None Returns the original rename result if the platform permits replacement.
        #@error Propagates filesystem errors, including platforms that already refuse rename replacement.
        #@effect Creates the competing fixture before calling the original rename implementation.
        def competing_rename(staged, destination):
            Path(destination).write_bytes(competing_bytes)
            return original_rename(staged, destination)

        # Insert a competing file at the hard-link boundary and require atomic create-only behavior.
        #@param staged Path Completed temporary source archive offered for publication.
        #@param destination Path Output path occupied immediately before the link syscall.
        #@return None Does not return when the occupied output is correctly rejected.
        #@error Propagates FileExistsError from the real hard-link publication syscall.
        #@effect Creates only the disposable competing fixture; leaves its bytes intact.
        def competing_link(staged, destination):
            Path(destination).write_bytes(competing_bytes)
            return original_link(staged, destination)

        with mock.patch.object(BUNDLE.os, 'rename', competing_rename), \
                mock.patch.object(BUNDLE.os, 'link', competing_link):
            with self.assertRaises(FileExistsError):
                BUNDLE.bundle(profile, self.root, output)
        self.assertEqual(output.read_bytes(), competing_bytes)
        self.assertEqual(set(self.root.iterdir()), {source, output})

    # Treat a dangling output symlink as occupied rather than replacing a caller-owned directory entry.
    #@param self SourceAuditTest Owns the source fixture and deliberately dangling link.
    #@return None Assertions require an existing-output error and preservation of the link target text.
    #@error Skips only when the current host cannot create symlinks for this fixture.
    #@effect Creates a disposable dangling link without creating or modifying its missing target.
    def test_bundle_preserves_dangling_output_symlink(self):
        source = self.root / 'upstream.txt'
        source.write_bytes(b'original source')
        profile = {'schema': 'yaca-corresponding-source-inputs-v1', 'tool': 'fixture', 'version': '1',
                   'inputs': [{'path': source.name, 'destination': 'source.txt',
                               'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}]}
        output = self.root / 'dangling.tar.gz'
        missing_target = self.root / 'missing-target'
        try:
            output.symlink_to(missing_target)
        except OSError as error:
            self.skipTest('host cannot create the dangling symlink fixture: ' + str(error))
        original_link_target = output.readlink()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            BUNDLE.bundle(profile, self.root, output)
        self.assertTrue(output.is_symlink())
        self.assertEqual(output.readlink(), original_link_target)
        self.assertFalse(missing_target.exists())

    # Reject changed input bytes and executable distributions before publishing a source bundle.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require both failures and no accepted output archive.
    #@effect Rewrites only this test's input fixture and attempts production bundling.
    def test_production_bundle_rejects_changed_or_binary_inputs(self):
        source = self.root / 'input'
        source.write_bytes(b'original source')
        profile = {'schema': 'yaca-corresponding-source-inputs-v1', 'tool': 'fixture', 'version': '1',
                   'inputs': [{'path': source.name, 'destination': 'source.dat',
                               'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}]}
        output = self.root / 'rejected.tar.gz'
        source.write_bytes(b'changed source')
        with self.assertRaisesRegex(ValueError, 'differs'):
            BUNDLE.bundle(profile, self.root, output)
        source.write_bytes(b'MZ binary distribution')
        profile['inputs'][0]['sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, 'compiled distribution'):
            BUNDLE.bundle(profile, self.root, output)
        self.assertFalse(output.exists())

    # Keep source-profile input paths confined to their declared cache rather than accepting traversal.
    #@param self SourceAuditTest Fixture owner.
    #@return None No value; assertions require an unsafe-path error before any output exists.
    #@effect Attempts bundling using an invalid path record without reading outside the owned input root.
    def test_source_input_traversal_is_rejected(self):
        profile = {'schema': 'yaca-corresponding-source-inputs-v1', 'tool': 'fixture', 'version': '1',
                   'inputs': [{'path': '../outside', 'destination': 'source', 'sha256': '0' * 64}]}
        output = self.root / 'rejected-traversal.tar.gz'
        with self.assertRaisesRegex(ValueError, 'unsafe corresponding-source input path'):
            BUNDLE.bundle(profile, self.root, output)
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
