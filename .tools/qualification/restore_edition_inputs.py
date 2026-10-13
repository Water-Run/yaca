#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-13
# File: restore_edition_inputs.py
# Description: Recover verified toolbox payloads, source attachments and their declared closure status without carrying over the old core or qualification.

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('yaca_restore_audit', ROOT / '.tools/qualification/audit_editions.py')
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


# Copy one already audited member and confirm its bytes before exposing it as a staging input.
#@param archive ZipFile Caller-owned runtime or companion archive, kept open throughout recovery.
#@param name str Canonical member name accepted by the production audit.
#@param destination Path Absent file within the private recovery staging tree.
#@param expected str SHA-256 recorded in the admitted edition metadata.
#@param executable bool Whether the portable file requires executable mode.
#@return None No result; the verified file is ready for later assembly.
#@error Raises on duplicate destinations, CRC/hash mismatch or filesystem failure.
#@effect Creates only the selected member and its parents; never extracts the whole archive.
def copy_member(archive, name, destination, expected, executable):
    AUDIT.PACKAGING.safe_destination(name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    value = hashlib.sha256()
    with archive.open(name) as source, destination.open('xb') as target:
        while chunk := source.read(1048576):
            target.write(chunk)
            value.update(chunk)
    if value.hexdigest() != expected:
        raise ValueError('recovered member digest differs: ' + name)
    destination.chmod(0o755 if executable else 0o644)


# Recover one explicit target's toolbox inputs, excluding the old product core and its evidence.
#@param runtime Path Existing clean/std/full runtime ZIP with its original edition basename.
#@param notices Path Matching notices ZIP containing edition metadata and corresponding sources.
#@param target str Expected target identity; mismatched pairs are rejected before output creation.
#@param output Path Absent directory receiving tools, sources and an input manifest atomically.
#@param catalog Path Current pinned tool catalog used by the production audit and later assembler.
#@return dict Recovery receipt binding original pair bytes, target, tool IDs and retained source digests.
#@error Raises for damaged archives, target mismatch, existing output, case-insensitive Linux staging or changed inputs during recovery.
#@effect Reads/audits the pair and creates a new local staging directory; no programs run or network requests occur.
#@ownership Recovery retains toolbox files, source archives and declared closure status; old core tests and qualification are not adopted.
def restore(runtime, notices, target, output, catalog=ROOT / 'release/tool-bundles.json'):
    output = output.absolute()
    if output.exists():
        raise ValueError('recovery output already exists')
    audited = AUDIT.audit_pair(runtime, notices, catalog)
    if audited['target'] != target:
        raise ValueError('edition pair belongs to another target')
    if audited['tool_payload_gaps']:
        raise ValueError('edition toolbox payload is incomplete')
    specification = json.loads(Path(catalog).read_text(encoding='utf-8'))
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.yaca-recovered-tools-', dir=output.parent) as temporary:
        stage = Path(temporary)
        if target == 'linux-x86_64':
            probe = stage / 'YacaCaseProbe'
            probe.touch(exist_ok=False)
            if (stage / 'yacacaseprobe').exists():
                raise ValueError('Linux toolbox recovery requires a case-sensitive output filesystem')
            probe.unlink()
        with zipfile.ZipFile(runtime) as payload, zipfile.ZipFile(notices) as companion:
            summary = AUDIT.document_json(companion, 'edition.json')
            inputs = {'schema': 'yaca-tool-inputs-v1', 'target': target, 'tools': []}
            source_receipts = []
            for tool in summary['tools']:
                prefix = 'tools/' + specification['tools'][tool['id']]['directory'] + '/'
                files = []
                for item in summary['files']:
                    name = item['destination']
                    if name.startswith(prefix):
                        copy_member(payload, name, stage / name, item['sha256'], item['executable'])
                        files.append({'source': name, 'destination': name, 'sha256': item['sha256'],
                                      'executable': item['executable']})
                source = tool['source_archive']
                name = source['destination']
                copy_member(companion, name, stage / name, source['sha256'], False)
                recovered = {key: tool[key] for key in
                             ('id', 'version', 'entry_points', 'license_id', 'license_files', 'source_url')}
                recovered['files'] = files
                recovered['source_archive'] = {'source': name, 'sha256': source['sha256']}
                if 'source_closure' in tool:
                    recovered['source_closure'] = tool['source_closure']
                inputs['tools'].append(recovered)
                source_receipts.append({'tool': tool['id'], 'path': name, 'sha256': source['sha256']})
            index = next((item for item in summary['files'] if item['destination'] == 'tools/INDEX.txt'), None)
            if index:
                copy_member(payload, 'tools/INDEX.txt', stage / 'tools/INDEX.txt', index['sha256'], index['executable'])
        if AUDIT.PACKAGING.digest(runtime) != audited['archive_sha256'] \
                or AUDIT.PACKAGING.digest(notices) != audited['notices_sha256']:
            raise ValueError('edition pair changed during recovery')
        receipt = {'schema': 'yaca-restored-tool-inputs-v1', 'status': 'PASS', 'target': target,
                   'source_edition': audited['edition'], 'source_runtime_sha256': audited['archive_sha256'],
                   'source_notices_sha256': audited['notices_sha256'],
                   'tools': [item['id'] for item in inputs['tools']], 'sources': source_receipts,
                   'old_core_adopted': False, 'old_qualification_adopted': False, 'release_authorized': False}
        (stage / 'tool-inputs.json').write_text(json.dumps(inputs, indent=2) + '\n', encoding='utf-8')
        (stage / 'recovery.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
        os.rename(stage, output)
    return receipt


# Recover one explicitly named edition pair as reusable, byte-verified build inputs.
#@param none Parses runtime, notices, target, catalog and absent output directory from argv.
#@return None Prints PASS with the recovered target and tool count; failure exits nonzero.
#@error Argument errors and recovery failures exit without replacing existing directories.
#@effect Creates the requested recovery tree; never builds, executes, downloads or publishes software.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--notices', type=Path, required=True)
    parser.add_argument('--target', choices=['win32-x86', 'win64-x86_64', 'linux-x86_64'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--catalog', type=Path, default=ROOT / 'release/tool-bundles.json')
    args = parser.parse_args()
    try:
        receipt = restore(args.runtime, args.notices, args.target, args.output, args.catalog)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, 'tool-input-recovery=FAIL ' + str(error) + '\n')
    print('tool-input-recovery=PASS target=' + receipt['target'] + ' tools=' + str(len(receipt['tools'])))


if __name__ == '__main__':
    main()
