#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-15
# File: bundle_corresponding_sources.py
# Description: Assemble exact toolbox corresponding-source profiles from pinned source archives and maintained recipes, with verified member digests and no binary-only fallback.

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import tarfile
import tempfile


# Hash one regular pinned source or recipe without accepting a final symlink.
#@param path Path Existing source archive or build recipe.
#@return str SHA-256 digest of all bytes.
#@error Raises for missing/nonregular inputs or failed reads.
#@effect Reads the selected file in bounded chunks.
def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('source profile input is not regular: ' + str(path))
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


# Create one byte-bound source archive without replacing an existing artifact.
#@param profile dict Explicit tool/version and pinned input records containing path, destination and SHA-256.
#@param input_root Path Cache root for inputs whose origin is absent or cache; repository inputs use the maintained repository root.
#@param output Path Absent .tar.gz artifact receiving the verified corresponding-source closure.
#@return dict Source profile with exact member hashes; it does not grant runtime or release qualification.
#@error Raises on binary-only inputs, unsafe/duplicate paths, mismatched hashes, occupied outputs or unavailable hard-link publication.
#@effect Reads pinned sources, creates a deterministic temporary tar.gz and atomically links verified bytes to an absent output; temporary files are cleaned on failure.
def bundle(profile, input_root, output):
    output = Path(output)
    if os.path.lexists(output):
        raise ValueError('corresponding-source output already exists')
    if profile.get('schema') != 'yaca-corresponding-source-inputs-v1' \
            or not isinstance(profile.get('inputs'), list) or not profile['inputs']:
        raise ValueError('invalid corresponding-source input profile')
    admitted = []
    names = set()
    for item in profile['inputs']:
        name = item['destination']
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or name == 'source-profile.json' or name in names:
            raise ValueError('unsafe or duplicate corresponding-source destination')
        names.add(name)
        origin = item.get('origin', 'cache')
        if origin not in ('cache', 'repository'):
            raise ValueError('unknown corresponding-source input origin')
        base = Path(input_root).resolve() if origin == 'cache' else Path(__file__).resolve().parents[2]
        input_path = PurePosixPath(item['path'])
        if input_path.is_absolute() or '..' in input_path.parts:
            raise ValueError('unsafe corresponding-source input path')
        source = base / item['path']
        if not source.resolve().is_relative_to(base):
            raise ValueError('corresponding-source input escapes its declared root')
        if digest(source) != item['sha256']:
            raise ValueError('pinned corresponding source differs: ' + item['path'])
        with source.open('rb') as stream:
            magic = stream.read(4)
        if magic.startswith(b'MZ') or magic == b'\x7fELF':
            raise ValueError('compiled distribution cannot replace corresponding source')
        admitted.append((source, name, item['sha256']))
    record = {'schema': 'yaca-corresponding-source-v1', 'tool': profile['tool'], 'version': profile['version'],
              'provenance': profile.get('provenance', {}),
              'files': [{'path': name, 'sha256': expected} for source, name, expected in admitted]}
    encoded = (json.dumps(record, indent=2) + '\n').encode('utf-8')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.yaca-corresponding-source-', dir=output.parent) as temporary:
        staged = Path(temporary) / output.name
        with staged.open('xb') as target, gzip.GzipFile(filename='', fileobj=target, mode='wb', mtime=946684800) as compressed:
            with tarfile.open(fileobj=compressed, mode='w') as archive:
                metadata = tarfile.TarInfo('source-profile.json')
                metadata.size, metadata.mode, metadata.mtime = len(encoded), 0o644, 946684800
                archive.addfile(metadata, io.BytesIO(encoded))
                for source, name, expected in admitted:
                    member = tarfile.TarInfo(name)
                    member.size, member.mode, member.mtime = source.stat().st_size, 0o644, 946684800
                    with source.open('rb') as stream:
                        archive.addfile(member, stream)
                    if digest(source) != expected:
                        raise ValueError('source changed during bundle creation')
        with tarfile.open(staged) as archive:
            for source, name, expected in admitted:
                with archive.extractfile(name) as stream:
                    if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                        raise ValueError('bundled source bytes differ')
        # The same-directory hard link fails atomically if another writer occupies the output.
        # A rename after an existence check could replace that writer's file on POSIX.
        os.link(staged, output)
    return record


# Bundle one explicit pinned profile without downloading or executing its inputs.
#@param none Parses profile JSON, input root and absent output archive from argv.
#@return None Prints the tool and verified member count; failures exit nonzero.
#@error Invalid inputs and filesystem failures exit without replacing an existing archive.
#@effect Creates one corresponding-source archive; no compiler, install or network action runs.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', type=Path)
    parser.add_argument('input_root', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = bundle(json.loads(args.profile.read_text()), args.input_root, args.output)
    print('corresponding-source-bundle=PASS tool=' + result['tool'] + ' members=' + str(len(result['files'])))


if __name__ == '__main__':
    main()
