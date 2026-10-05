#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: attach_windows_test_summary.py
# Description: Bind a successful Windows full-suite receipt and raw log to the exact candidate core and source snapshot.

import argparse
import hashlib
import json
import pathlib
import re
import shutil


# Compute the SHA-256 of an existing regular input without following a final symlink.
#@param path Path Candidate core, source archive or captured test log.
#@return str Lowercase SHA-256 of the complete file.
#@error Raises when the file is missing or a symlink, or when reading fails.
#@effect Reads the selected file in bounded chunks.
def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('evidence input must be a regular file: '+str(path))
    value=hashlib.sha256()
    with path.open('rb') as source:
        while chunk:=source.read(1048576):
            value.update(chunk)
    return value.hexdigest()


# Validate and attach the target receipt without granting release or using another target's test count.
#@param none Parses BUILD, RECEIPT and LOG paths from the command line.
#@return None No result; prints PASS after byte bindings and the full-suite outcome have been checked.
#@error Raises on mismatched core/source/log/target, incomplete tests or an authorized release directory.
#@effect Adds the raw test log and receipt to the candidate companion and updates its build summary.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build',type=pathlib.Path)
    parser.add_argument('receipt',type=pathlib.Path)
    parser.add_argument('log',type=pathlib.Path)
    args=parser.parse_args()
    docs=args.build/'companion/docs'
    summary_path=docs/'build-summary.json'
    digest(summary_path)
    digest(args.receipt)
    receipt=json.loads(args.receipt.read_text(encoding='utf-8'))
    summary=json.loads(summary_path.read_text(encoding='utf-8'))
    if summary.get('release_authorized') is not False or summary.get('target_qualification_complete') is not False:
        raise ValueError('only unqualified candidate evidence can be updated')
    target=summary.get('target')
    if target not in ('win32-x86','win64-x86_64') or receipt.get('target')!=target:
        raise ValueError('test receipt belongs to another target')
    if receipt.get('schema')!='yaca-target-full-test-v1' or receipt.get('status')!='PASS' \
            or type(receipt.get('exit_code')) is not int or receipt['exit_code']!=0:
        raise ValueError('target process did not report a successful full suite')
    core=digest(args.build/'package/yaca.exe')
    snapshot=digest(args.build/'yaca-source.tar.gz')
    artifact_hashes=[item.get('sha256') for item in summary.get('artifacts',[])
                     if item.get('path')=='package/yaca.exe']
    if receipt.get('core_sha256')!=core or receipt.get('source_archive_sha256')!=snapshot \
            or summary.get('source_snapshot_sha256')!=snapshot or artifact_hashes!=[core]:
        raise ValueError('target tests do not bind this core and source snapshot')
    if receipt.get('log_sha256')!=digest(args.log):
        raise ValueError('target test log differs from its receipt')
    if args.log.stat().st_size>8*1024*1024:
        raise ValueError('target test log exceeds its evidence bound')
    matches=re.findall(rb'^SUMMARY total=([0-9]+) passed=([0-9]+) failed=([0-9]+)\r?$',args.log.read_bytes(),re.M)
    if len(matches)!=1:
        raise ValueError('target log has no unique full-suite summary')
    total,passed,failed=map(int,matches[0])
    if total<1 or total!=passed or failed!=0 \
            or any(type(receipt.get(key)) is not int or receipt[key]!=value
                   for key,value in (('total',total),('passed',passed),('failed',failed))):
        raise ValueError('target suite counts are incomplete or inconsistent')
    if receipt.get('command')!='yaca.exe --lua -E source/test/run.lua':
        raise ValueError('receipt is not for the complete captured source suite')
    if not isinstance(receipt.get('environment'),str) or not receipt['environment']:
        raise ValueError('target environment is missing')
    source_record=dict(receipt)
    source_record['log']='full-test-target.log'
    if args.log.resolve()!=(docs/'full-test-target.log').resolve():
        shutil.copyfile(args.log,docs/'full-test-target.log')
    (docs/'full-test-summary.json').write_text(json.dumps(source_record,indent=2)+'\n',encoding='utf-8')
    summary['full_tests']=str(passed)+'/'+str(total)
    summary['full_test_evidence']={'receipt':'full-test-summary.json','log':'full-test-target.log',
                                   'log_sha256':receipt['log_sha256'],'core_sha256':core,
                                   'source_snapshot_sha256':snapshot,'environment':receipt['environment']}
    summary_path.write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print('target-full-tests=PASS target='+target+' counts='+summary['full_tests'])


if __name__=='__main__':
    main()
