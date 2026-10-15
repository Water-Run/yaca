#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-15
# File: verify_source_signatures.py
# Description: Verify byte-pinned detached source signatures against explicitly permitted primary keys in an isolated GnuPG home, without granting source closure or release qualification.

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile


# Stage one byte-pinned public input so verification cannot race subsequent cache changes.
#@param root Path Explicit cache root containing the declared input.
#@param record dict Relative path and lowercase SHA-256, with optional descriptive metadata.
#@param destination Path Absent file in the caller-owned temporary verification directory.
#@return Path Staged regular file whose copied bytes match the declared digest.
#@error Rejects unsafe paths, final symlinks, root escapes, invalid digests and changed bytes.
#@effect Reads the cache and writes a new temporary file; never executes input bytes.
def stage_input(root, record, destination):
    if not isinstance(record, dict):
        raise ValueError('signature input must be an object')
    name, expected = record.get('path'), record.get('sha256')
    if not isinstance(name, str) or not name or '\\' in name \
            or PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts:
        raise ValueError('unsafe signature input path')
    if not isinstance(expected, str) or not re.fullmatch(r'[0-9a-f]{64}', expected):
        raise ValueError('signature input requires lowercase SHA-256')
    root = Path(root).resolve()
    source = root / name
    if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(root):
        raise ValueError('signature input is not a regular file within its root')
    actual = hashlib.sha256()
    with source.open('rb') as stream, destination.open('xb') as target:
        while chunk := stream.read(1048576):
            actual.update(chunk)
            target.write(chunk)
    if actual.hexdigest() != expected:
        raise ValueError('signature input SHA-256 differs: ' + name)
    return destination


# Verify one detached signature using only byte-pinned keys and the declared primary fingerprints.
#@param entry dict Source, signature, nonempty keys and permitted full primary_fingerprints.
#@param input_root Path Cache root for all pinned files.
#@param gpg str Installed GnuPG executable used only to dearmor staged public keys.
#@param gpgv str Installed verification executable; no default keyring is accepted.
#@return dict PASS result with actual signing fingerprints and GnuPG status transcript.
#@error Raises on pending inputs, malformed pins, tool failure, bad signatures or another primary key.
#@effect Stages public bytes, runs bounded installed GnuPG tools in a disposable home, then removes temporary files.
def verify_entry(entry, input_root, gpg='gpg', gpgv='gpgv'):
    if not isinstance(entry, dict) or entry.get('status') not in (None, 'recovered'):
        raise ValueError('signature input remains pending')
    permitted = entry.get('primary_fingerprints')
    if not isinstance(permitted, list) or not permitted or any(
            not isinstance(value, str) or not re.fullmatch(r'[0-9A-F]{40}|[0-9A-F]{64}', value)
            for value in permitted):
        raise ValueError('full primary signing fingerprints are required')
    keys = entry.get('keys')
    if not isinstance(keys, list) or not keys:
        raise ValueError('pinned public signing keys are required')
    with tempfile.TemporaryDirectory(prefix='yaca-source-signature-') as temporary:
        work = Path(temporary)
        source = stage_input(input_root, entry.get('source'), work / 'source')
        signature = stage_input(input_root, entry.get('signature'), work / 'signature')
        # Relative names also work with MSYS GnuPG, which parses drive-letter keyrings as resource URLs.
        command = [gpgv, '--homedir', '.', '--status-fd', '1']
        for index, record in enumerate(keys):
            key = stage_input(input_root, record, work / ('key-' + str(index) + '.asc'))
            keyring = work / ('key-' + str(index) + '.gpg')
            subprocess.run([gpg, '--no-options', '--batch', '--homedir', '.',
                            '--dearmor', '--output', keyring.name, key.name], check=True,
                           capture_output=True, timeout=30, cwd=work)
            command.extend(['--keyring', './' + keyring.name])
        result = subprocess.run([*command, signature.name, source.name], capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=60, cwd=work)
        signatures = []
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) >= 11 and fields[:2] == ['[GNUPG:]', 'VALIDSIG']:
                primary = fields[11] if len(fields) >= 12 else fields[2]
                signatures.append({'signing_fingerprint': fields[2], 'primary_fingerprint': primary,
                                   'created': fields[3], 'hash_algorithm': fields[9]})
        if result.returncode or not signatures:
            raise ValueError('gpgv rejected detached signature: ' + result.stdout.strip()
                             + '\n' + result.stderr.strip())
        if any(record['primary_fingerprint'] not in permitted for record in signatures):
            raise ValueError('verified signature uses an unpermitted primary fingerprint')
        return {'id': entry.get('id'), 'status': 'PASS', 'signatures': signatures,
                'gpgv_status': result.stdout, 'gpgv_diagnostics': result.stderr,
                'source': entry['source'], 'signature': entry['signature'], 'keys': keys}


# Verify every explicitly listed source signature while retaining per-entry failures.
#@param manifest dict Nonempty yaca-detached-source-signatures-v1 entries with unique string IDs.
#@param input_root Path Existing public cache root used for all relative inputs.
#@param gpg str Installed dearmor executable, default gpg.
#@param gpgv str Installed verifier executable, default gpgv.
#@return dict Aggregate PASS/FAIL, individual diagnostics and explicit nonqualification boundaries.
#@error Rejects malformed or duplicate manifest entries; individual verification failures become FAIL rows.
#@effect Reads pinned files and runs isolated verification sequentially; does not download or execute sources.
def verify_manifest(manifest, input_root, gpg='gpg', gpgv='gpgv'):
    if not isinstance(manifest, dict) or manifest.get('schema') != 'yaca-detached-source-signatures-v1' \
            or not isinstance(manifest.get('entries'), list) or not manifest['entries']:
        raise ValueError('invalid or empty detached-signature manifest')
    ids = set()
    results = []
    for entry in manifest['entries']:
        if not isinstance(entry, dict) or not isinstance(entry.get('id'), str) or not entry['id'] or entry['id'] in ids:
            raise ValueError('invalid or duplicate signature entry ID')
        ids.add(entry['id'])
        try:
            result = verify_entry(entry, input_root, gpg, gpgv)
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            result = {'id': entry['id'], 'status': 'FAIL', 'reason': str(error)}
        results.append(result)
    return {'schema': 'yaca-source-signature-verification-v1',
            'status': 'PASS' if all(row['status'] == 'PASS' for row in results) else 'FAIL',
            'results': results, 'release_authorized': False, 'complete_source_closure': False,
            'key_expiration_and_revocation': 'not-evaluated-by-gpgv',
            'manual_binary_correspondence_review': 'required'}


# Verify a pinned signature manifest and save an absent optional evidence report.
#@param none Parses manifest, input root, optional report and installed executable names from argv.
#@return None Prints aggregate verification status; exits one on any failed signature.
#@error Invalid input, unavailable tools or occupied report paths cause a nonzero exit.
#@effect Reads only public pinned files, runs installed verifiers and optionally creates a new JSON report.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('input_root', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--gpg', default='gpg')
    parser.add_argument('--gpgv', default='gpgv')
    args = parser.parse_args()
    result = verify_manifest(json.loads(args.manifest.read_text(encoding='utf-8')), args.input_root, args.gpg, args.gpgv)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8', newline='\n') as stream:
            json.dump(result, stream, indent=2)
            stream.write('\n')
    passed = sum(row['status'] == 'PASS' for row in result['results'])
    print('source-signatures=' + result['status'] + ' passed=' + str(passed) + '/' + str(len(result['results'])))
    if result['status'] != 'PASS':
        parser.exit(1)


if __name__ == '__main__':
    main()
