#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-11
# File: audit_corresponding_sources.py
# Description: Reject binary distributions masquerading as toolbox corresponding sources and verify explicit source-profile members against their byte digests.

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


# Read a regular source attachment and detect known binary-only or damaged source profiles.
#@param path Path Existing toolbox source attachment; final symlinks are rejected.
#@return dict Structural source report with detected kind, member count and all observed findings.
#@error Raises for unreadable inputs or malformed tar headers; never extracts or executes members.
#@effect Reads source archive bytes and bounded profile metadata without changing the input.
def inspect(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError('corresponding source is not a regular file')
    with path.open('rb') as source:
        magic = source.read(8)
    report = {'kind': 'unclassified', 'members': 0, 'findings': [], 'profile_verified': False}
    if magic.startswith(b'MZ') or magic.startswith(b'\x7fELF'):
        report['kind'] = 'binary-distribution'
        report['findings'].append('compiled distribution cannot serve as corresponding source')
        return report
    if not tarfile.is_tarfile(path):
        return report
    report['kind'] = 'tar-archive'
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        files = {}
        for member in members:
            relative = PurePosixPath(member.name)
            if relative.is_absolute() or '..' in relative.parts or member.issym() or member.islnk() \
                    or not (member.isfile() or member.isdir()):
                report['findings'].append('unsafe source archive member: ' + member.name)
                continue
            if member.isfile():
                if member.name in files:
                    report['findings'].append('duplicate source member: ' + member.name)
                files[member.name] = member
        report['members'] = len(files)
        if len(files) == 1 and next(iter(files)).endswith('-portable.zip'):
            report['findings'].append('portable binary ZIP alone is not a corresponding-source closure')
        if 'source-profile.json' not in files:
            return report
        profile_member = files['source-profile.json']
        if profile_member.size > 1048576:
            report['findings'].append('source profile exceeds its metadata bound')
            return report
        with archive.extractfile(profile_member) as stream:
            profile = json.load(stream)
        if not isinstance(profile, dict) or profile.get('schema') != 'yaca-corresponding-source-v1' \
                or not isinstance(profile.get('files'), list) or not profile['files']:
            report['findings'].append('invalid or empty corresponding-source profile')
            return report
        expected = set()
        for record in profile['files']:
            if not isinstance(record, dict) or set(record) != {'path', 'sha256'} \
                    or not isinstance(record['path'], str) or record['path'] == 'source-profile.json' \
                    or record['path'] in expected or record['path'] not in files:
                report['findings'].append('invalid, missing or duplicate source-profile member')
                continue
            expected.add(record['path'])
            with archive.extractfile(files[record['path']]) as stream:
                value = hashlib.file_digest(stream, 'sha256').hexdigest()
            if value != record['sha256']:
                report['findings'].append('source-profile digest differs: ' + record['path'])
        if set(files) != expected | {'source-profile.json'}:
            report['findings'].append('source archive membership differs from its profile')
        report['profile_verified'] = not report['findings']
    return report


# Inspect all source attachments of one explicit toolbox input manifest without authorizing release.
#@param input_manifest Path Existing yaca-tool-inputs-v1 manifest whose source paths resolve relative to its directory.
#@return dict Aggregate structural report with per-tool findings; manual closure review remains a separate requirement.
#@error Raises for an invalid manifest or unreadable source files.
#@effect Reads only declared source attachments and produces a report in memory.
def audit(input_manifest):
    input_manifest = Path(input_manifest)
    inputs = json.loads(input_manifest.read_text(encoding='utf-8'))
    if inputs.get('schema') != 'yaca-tool-inputs-v1':
        raise ValueError('unsupported toolbox input schema')
    tools = []
    for tool in inputs['tools']:
        source = tool['source_archive']
        path = input_manifest.parent / source['source']
        result = inspect(path)
        with path.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        if actual != source['sha256']:
            result['findings'].append('source attachment differs from the toolbox input digest')
        result['tool'] = tool['id']
        result['source'] = source['source']
        tools.append(result)
    return {'schema': 'yaca-corresponding-source-audit-v1', 'target': inputs['target'],
            'status': 'FAIL' if any(item['findings'] for item in tools) else 'structurally-checked',
            'manual_source_closure_review': 'required', 'release_authorized': False, 'tools': tools}


# Emit a structural source audit and fail on actual misleading or damaged attachments.
#@param none Parses an explicit toolbox input manifest and an absent optional report path.
#@return None Prints target/status; failures exit nonzero after preserving the report.
#@error Argument, source or report-write errors exit nonzero; existing reports are not replaced.
#@effect Reads declared source archives and optionally creates a public JSON report; no software runs or downloads occur.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.inputs)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as destination:
            json.dump(result, destination, indent=2)
            destination.write('\n')
    print('corresponding-source-audit=' + result['status'] + ' target=' + result['target'])
    if result['status'] == 'FAIL':
        parser.exit(1)


if __name__ == '__main__':
    main()
