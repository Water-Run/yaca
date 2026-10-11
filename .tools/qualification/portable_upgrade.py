#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-11
# File: portable_upgrade.py
# Description: Replaces a stopped isolated Linux test core while verifying every configuration, Context and workspace byte remains unchanged.

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil


# Hash one regular file without following a final symbolic link.
#@param path Path Existing file selected for a core or data inventory.
#@return str Exact SHA-256 of all file bytes.
#@error Rejects missing/nonregular files and symbolic links.
#@effect Reads the file in bounded blocks without changing it.
def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('upgrade input must be a regular file')
    with path.open('rb') as stream:
        value = hashlib.sha256()
        while True:
            block = stream.read(1048576)
            if not block:
                return value.hexdigest()
            value.update(block)


# Capture the complete owned data set without exporting private file contents or per-file hashes.
#@param root Path Isolated application directory containing __yaca__ and workspace.
#@return list[tuple] Sorted directory names and file names/sizes/digests retained only in memory.
#@error Refuses missing data roots, links or nonregular entries.
#@effect Reads all configuration, Context and workspace files.
def inventory(root):
    records = []
    for leaf in ('__yaca__', 'workspace'):
        base = root / leaf
        if not base.is_dir() or base.is_symlink():
            raise ValueError('isolated upgrade data root is unavailable')
        for directory, directories, names in os.walk(base):
            current = Path(directory)
            records.append(('directory', current.relative_to(root).as_posix()))
            for name in directories + names:
                if (current / name).is_symlink():
                    raise ValueError('upgrade data contains a symbolic link')
            for name in names:
                path = current / name
                records.append(('file', path.relative_to(root).as_posix(), path.stat().st_size, digest(path)))
    return sorted(records)


# Replace only the already stopped executable and verify the preserved data before the caller reopens its Context.
#@param root Path Isolated application directory; caller has confirmed its previous process exited.
#@param replacement Path Different new core whose bytes were built and verified separately.
#@param receipt Path Absent public receipt path outside __yaca__ and workspace.
#@return dict Old/new core digests and the unchanged-data result.
#@error Rejects existing receipt/temp output, identical cores or changed copied/data bytes.
#@effect Copies to a new sibling file, preserves executable mode, atomically replaces yaca and writes the receipt.
def replace_core(root, replacement, receipt):
    root = root.resolve()
    replacement = replacement.resolve()
    receipt = receipt.absolute()
    if receipt.exists():
        raise ValueError('upgrade receipt already exists')
    for leaf in ('__yaca__', 'workspace'):
        if (root / leaf) == receipt or (root / leaf) in receipt.parents:
            raise ValueError('receipt cannot modify the preserved data set')
    core = root / 'yaca'
    old_digest, new_digest = digest(core), digest(replacement)
    if old_digest == new_digest:
        raise ValueError('upgrade must change core bytes')
    before = inventory(root)
    temporary = root / 'yaca.upgrade-partial'
    with replacement.open('rb') as source, temporary.open('xb') as destination:
        shutil.copyfileobj(source, destination, 1048576)
        destination.flush()
        os.fsync(destination.fileno())
    os.chmod(temporary, core.stat().st_mode & 0o777)
    if digest(temporary) != new_digest:
        raise ValueError('copied upgrade core differs')
    os.replace(temporary, core)
    if inventory(root) != before:
        raise ValueError('core replacement altered preserved data')
    result = {'old_core_sha256': old_digest, 'new_core_sha256': new_digest,
              'data_entries': len(before), 'all_data_bytes_preserved': True}
    with receipt.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    return result


# Execute one explicitly staged retained-data replacement without starting a model or application.
#@param none Reads root, replacement and absent receipt paths from command-line arguments.
#@return None No value; prints PASS only after core and data checks succeed.
#@error Filesystem or validation failures exit nonzero through the normal exception path.
#@effect Runs only the selected isolated core replacement.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('replacement', type=Path)
    parser.add_argument('receipt', type=Path)
    args = parser.parse_args()
    result = replace_core(args.root, args.replacement, args.receipt)
    print('portable-upgrade=PASS data_entries=' + str(result['data_entries']))


if __name__ == '__main__':
    main()
