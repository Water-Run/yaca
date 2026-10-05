#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: source_snapshot.py
# Description: Snapshot maintained working-tree sources, including pending changes, without copying ignored build data or credentials.

import argparse
import hashlib
import gzip
import json
import os
import pathlib
import stat
import subprocess
import tarfile
import tempfile


# Hash a maintained source or newly created archive in bounded blocks.
#@param path Path Existing regular file whose exact bytes are recorded.
#@return str Lowercase SHA-256 through EOF.
#@effect Reads the file without modifying it.
def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as source:
        while True:
            chunk=source.read(1024*1024)
            if not chunk:
                return value.hexdigest()
            value.update(chunk)


# Freeze tracked and nonignored new sources into an explicit working-tree archive.
#@param root Path Git repository root; source symlinks and submodules are rejected.
#@param output Path Absent directory receiving the archive and byte-bound manifest.
#@return dict Manifest containing base revision, dirty state, archive hash and member hashes.
#@error Rejects ignored/private data paths, nonregular sources or concurrent source changes.
#@effect Reads Git metadata and sources, then atomically publishes a new output directory.
def snapshot(root, output):
    root=root.resolve()
    output=output.absolute()
    if output.exists():
        raise ValueError('snapshot output already exists')
    names=subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=root).split(b'\0')
    names=sorted(set(name.decode('utf-8') for name in names if name))
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    dirty=bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=all'],cwd=root))
    files=[]
    for name in names:
        relative=pathlib.PurePosixPath(name)
        if relative.is_absolute() or any(part in ('..','') for part in relative.parts):
            raise ValueError('unsafe snapshot source path')
        if relative.parts[0] in ('out','build','obj','__yaca__','.git') or (
            relative.parts[0]=='bin' and name not in ('bin/list.txt','bin/LICENSE_THIRD_PARTY.txt')):
            raise ValueError('build or private data cannot enter the source snapshot')
        path=root/name
        if path.is_symlink() or not path.is_file() or any(parent.is_symlink() for parent in path.parents):
            raise ValueError('snapshot source must be regular: '+name)
        files.append({'path':name,'sha256':digest(path),'mode':stat.S_IMODE(path.stat().st_mode)})
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.yaca-source-',dir=output.parent) as temporary:
        stage=pathlib.Path(temporary)
        archive_path=stage/'yaca-source.tar.gz'
        with archive_path.open('xb') as target,gzip.GzipFile(filename='',fileobj=target,mode='wb',mtime=946684800) as compressed, \
                tarfile.open(fileobj=compressed,mode='w') as archive:
            for record in files:
                path=root/record['path']
                info=archive.gettarinfo(str(path),arcname=record['path'])
                if not info.isfile():
                    raise ValueError('source changed type during snapshot')
                info.uid=info.gid=0
                info.uname=info.gname=''
                info.mtime=946684800
                info.mode=record['mode']
                with path.open('rb') as source:
                    archive.addfile(info,source)
                if digest(path)!=record['sha256']:
                    raise ValueError('source changed during snapshot: '+record['path'])
        with tarfile.open(archive_path,'r:gz') as archive:
            for record in files:
                value=hashlib.sha256()
                with archive.extractfile(record['path']) as source:
                    while True:
                        chunk=source.read(1024*1024)
                        if not chunk:
                            break
                        value.update(chunk)
                if value.hexdigest()!=record['sha256']:
                    raise ValueError('archived source bytes differ: '+record['path'])
        manifest={'schema':'yaca-source-snapshot-v1','source_scope':'working-tree','base_revision':revision,
                  'dirty':dirty,'archive':'yaca-source.tar.gz','archive_sha256':digest(archive_path),'files':files}
        (stage/'snapshot.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
        os.rename(stage,output)
    return manifest


# Publish one source snapshot and report its exact archive binding.
#@param none No arguments; argparse reads repository and new output directory.
#@return None No value; malformed input exits nonzero without replacing existing output.
#@effect Creates the snapshot directory and prints only revision, digest and source count.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo',type=pathlib.Path)
    parser.add_argument('output',type=pathlib.Path)
    args=parser.parse_args()
    try:
        manifest=snapshot(args.repo,args.output)
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        parser.exit(1,'source-snapshot=FAIL '+str(error)+'\n')
    print('source-snapshot=PASS revision='+manifest['base_revision']+' sha256='+manifest['archive_sha256']
          +' files='+str(len(manifest['files']))+' scope=working-tree')


if __name__=='__main__':
    main()
