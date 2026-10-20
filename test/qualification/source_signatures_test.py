#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-20
# File: source_signatures_test.py
# Description: Exercise offline detached source verification, byte pins, permitted primary identities and actual expired/revoked primary or signing-subkey fixtures without requiring a signing agent.

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('source_signatures', ROOT / '.tools/qualification/verify_source_signatures.py')
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


#@class SourceSignatureTest Real offline signature checks using only public fixture bytes and installed verifiers.
#@field temporary TemporaryDirectory Owns disposable copies of public verification inputs.
#@field root Path Absolute fixture cache root.
#@field entry dict Valid public source/signature/key pins and expected primary fingerprint.
@unittest.skipUnless(all(shutil.which(name) for name in ('gpg', 'gpgv')), 'installed GnuPG verifiers required')
class SourceSignatureTest(unittest.TestCase):
    # Copy the independently generated public signature fixture into a disposable cache.
    #@param self SourceSignatureTest Owns the temporary public input files and their manifest.
    #@return None Stores source, public key and signature pins; registers directory cleanup.
    #@error Fails for missing or malformed maintained fixture data.
    #@effect Reads public JSON and writes fixture copies; no key generation, signing agent or network runs.
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='yaca-signature-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        fixture = json.loads((ROOT / 'test/fixtures/source-signature.json').read_text(encoding='utf-8'))
        source = self.root / 'source.txt'
        source.write_bytes(fixture['source'].encode('utf-8'))
        signature = self.root / 'source.txt.sig'
        signature.write_bytes(fixture['signature'].encode('ascii'))
        key = self.root / 'key.asc'
        key.write_bytes(fixture['public_key'].encode('ascii'))
        self.entry = {'id': 'fixture-1', 'source': self.pin(source), 'signature': self.pin(signature),
                      'keys': [self.pin(key)], 'primary_fingerprints': [fixture['primary_fingerprint']]}

    # Bind a public fixture file to the same manifest format used by recovered upstream signatures.
    #@param self SourceSignatureTest Owns the fixture cache root.
    #@param path Path Existing public source, signature or exported public key.
    #@return dict Relative path and SHA-256 of its exact bytes.
    #@effect Reads one small fixture file.
    def pin(self, path):
        return {'path': path.relative_to(self.root).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

    # Run production aggregate verification over the current single-entry manifest.
    #@param self SourceSignatureTest Owns the fixture pins and cache root.
    #@return dict Actual verification result including failure diagnostics.
    #@effect Stages public fixture bytes and runs real installed offline GnuPG verification.
    def verify(self):
        return VERIFY.verify_manifest({'schema': 'yaca-detached-source-signatures-v1', 'entries': [self.entry]}, self.root)

    # Select a frozen public key state while keeping the production source/signature/key pin format.
    #@param self SourceSignatureTest Owns the disposable cache and current verification entry.
    #@param state str Maintained valid-subkey, expired-primary, expired-subkey or revoked-primary fixture name.
    #@return dict Public fixture with exact primary/signing fingerprints for assertions.
    #@error Raises for missing fixture data or a failed disposable file write.
    #@effect Replaces only this test's public fixture files and in-memory pins; does not import private keys or start an agent.
    def use_key_state(self, state):
        fixture = json.loads((ROOT / 'test/fixtures/source-signature-key-states.json').read_text(encoding='utf-8'))['fixtures'][state]
        for name, field in (('source.txt', 'source'), ('source.txt.sig', 'signature'), ('key.asc', 'public_key')):
            (self.root / name).write_bytes(fixture[field].encode('utf-8'))
        self.entry = {'id': state, 'source': self.pin(self.root / 'source.txt'),
                      'signature': self.pin(self.root / 'source.txt.sig'),
                      'keys': [self.pin(self.root / 'key.asc')],
                      'primary_fingerprints': [fixture['primary_fingerprint']]}
        return fixture

    # Accept the real signature while keeping source closure and release authorization unresolved.
    #@param self SourceSignatureTest Owns the valid cryptographic fixture.
    #@return None Assertions require the actual primary fingerprint and explicit review boundaries.
    #@effect Runs production verification against the real detached signature.
    def test_valid_signature_does_not_grant_qualification(self):
        result = self.verify()
        self.assertEqual(result['status'], 'PASS', result)
        self.assertEqual(result['results'][0]['signatures'][0]['primary_fingerprint'], self.entry['primary_fingerprints'][0])
        self.assertFalse(result['complete_source_closure'])
        self.assertFalse(result['release_authorized'])
        self.assertEqual(result['key_expiration_and_revocation'], 'checked-against-pinned-keys')
        self.assertEqual(result['key_revocation_freshness'], 'not-checked')

    # Accept a valid signing subkey while retaining its permitted primary identity and snapshot boundary.
    #@param self SourceSignatureTest Owns public nonexpiring primary/signing-subkey fixtures.
    #@return None Assertions require both real verifiers to agree and forbid current online revocation claims.
    #@effect Runs only installed offline verification tools against public fixture bytes.
    def test_valid_subkey_is_checked_against_pinned_public_keys(self):
        fixture = self.use_key_state('valid-subkey')
        result = self.verify()
        self.assertEqual(result['status'], 'PASS', result)
        row = result['results'][0]
        self.assertEqual(row['signature_status'], 'PASS')
        self.assertEqual(row['signatures'][0]['signing_fingerprint'], fixture['signing_fingerprint'])
        self.assertEqual(row['signatures'][0]['primary_fingerprint'], fixture['primary_fingerprint'])
        self.assertEqual(row['key_validity']['status'], 'PASS')
        self.assertEqual(row['key_validity']['scope'], 'pinned-public-key-snapshot')
        self.assertEqual(row['key_validity']['rejected_statuses'], [])
        self.assertIsInstance(row['key_validity']['checked_at_epoch'], int)

    # Keep a mathematically valid historical signature separate from its currently expired primary key.
    #@param self SourceSignatureTest Owns a source signed in 2024 before the primary expired.
    #@return None Assertions require failed aggregate admission with retained successful cryptographic verification.
    #@effect Runs real gpgv and gpg against an already expired public fixture.
    def test_expired_primary_does_not_pass_on_validsig(self):
        self.use_key_state('expired-primary')
        result = self.verify()
        self.assertEqual(result['status'], 'FAIL', result)
        row = result['results'][0]
        self.assertEqual(row['signature_status'], 'PASS')
        self.assertEqual(row['key_validity']['status'], 'FAIL')
        self.assertIn('EXPKEYSIG', row['key_validity']['rejected_statuses'])

    # Check the actual signing subkey even when its nonexpiring primary fingerprint is permitted.
    #@param self SourceSignatureTest Owns a source signed before only the signing subkey expired.
    #@return None Assertions require expired-subkey rejection without discarding the correct primary identity.
    #@effect Runs real offline verifiers against the frozen public subkey-expiration fixture.
    def test_expired_signing_subkey_does_not_pass_on_primary_pin(self):
        fixture = self.use_key_state('expired-subkey')
        result = self.verify()
        self.assertEqual(result['status'], 'FAIL', result)
        row = result['results'][0]
        self.assertEqual(row['signature_status'], 'PASS')
        self.assertEqual(row['signatures'][0]['primary_fingerprint'], fixture['primary_fingerprint'])
        self.assertIn('EXPKEYSIG', row['key_validity']['rejected_statuses'])

    # Honor a real revocation certificate present in the pinned public-key snapshot.
    #@param self SourceSignatureTest Owns a valid source signature and its revoked primary public key.
    #@return None Assertions require REVKEYSIG rejection despite the successful mathematical signature check.
    #@effect Runs real offline verification without contacting a keyserver or starting a signing agent.
    def test_revoked_primary_does_not_pass_on_validsig(self):
        self.use_key_state('revoked-primary')
        result = self.verify()
        self.assertEqual(result['status'], 'FAIL', result)
        row = result['results'][0]
        self.assertEqual(row['signature_status'], 'PASS')
        self.assertEqual(row['key_validity']['status'], 'FAIL')
        self.assertIn('REVKEYSIG', row['key_validity']['rejected_statuses'])

    # Reject changed source bytes before a stale source pin can be treated as verified.
    #@param self SourceSignatureTest Owns the source fixture and original byte pin.
    #@return None Assertions require failure with a source digest diagnostic.
    #@effect Changes only the disposable source file and runs verification.
    def test_changed_source_pin_is_rejected(self):
        (self.root / 'source.txt').write_bytes(b'changed upstream source')
        result = self.verify()
        self.assertEqual(result['status'], 'FAIL')
        self.assertIn('SHA-256 differs', result['results'][0]['reason'])

    # Reject a forged source whose new byte hash is valid but whose detached signature is stale.
    #@param self SourceSignatureTest Owns the altered source and unchanged detached signature.
    #@return None Assertions require real cryptographic rejection rather than digest agreement alone.
    #@effect Rewrites the fixture and updates its source pin, then runs the real verifier.
    def test_rehashed_source_with_bad_signature_is_rejected(self):
        source = self.root / 'source.txt'
        source.write_bytes(b'changed upstream source')
        self.entry['source'] = self.pin(source)
        result = self.verify()
        self.assertEqual(result['status'], 'FAIL')
        self.assertIn('gpgv rejected', result['results'][0]['reason'])

    # Require the permitted primary identity even when a supplied key verifies the signature.
    #@param self SourceSignatureTest Owns the valid source/key/signature and deliberately wrong expected identity.
    #@return None Assertions require rejection of a cryptographically valid unpermitted signer.
    #@effect Changes only the in-memory permitted fingerprint and runs verification.
    def test_unpermitted_primary_fingerprint_is_rejected(self):
        self.entry['primary_fingerprints'] = ['0' * 40]
        result = self.verify()
        self.assertEqual(result['status'], 'FAIL')
        self.assertIn('unpermitted primary', result['results'][0]['reason'])

    # Bind public key and detached signature bytes independently from the source digest.
    #@param self SourceSignatureTest Owns valid fixture pins.
    #@return None Assertions require rejection for each independently incorrect key/signature hash.
    #@effect Changes in-memory pins and runs isolated verification without altering fixture bytes.
    def test_key_and_signature_pins_are_required(self):
        for record in (self.entry['keys'][0], self.entry['signature']):
            original = record['sha256']
            record['sha256'] = '0' * 64
            result = self.verify()
            self.assertEqual(result['status'], 'FAIL')
            self.assertIn('SHA-256 differs', result['results'][0]['reason'])
            record['sha256'] = original


if __name__ == '__main__':
    unittest.main()
