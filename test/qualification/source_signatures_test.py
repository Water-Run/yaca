#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-15
# File: source_signatures_test.py
# Description: Exercise real detached source verification using a frozen public OpenPGP fixture, altered sources, wrong pins and unpermitted primary fingerprints without requiring a signing agent.

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
        self.assertEqual(result['key_expiration_and_revocation'], 'not-evaluated-by-gpgv')

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
