#!/usr/bin/env python
# Author: WaterRun
# Date: 2026-10-05
# File: export_centos_runtime.py
# Description: Export signed CentOS 7 runtime/link libraries as explicit hashed inputs for the portable compiler SDK.

from __future__ import print_function
import argparse
import hashlib
import json
import os
import shutil
import subprocess


# Hash one source or exported library in bounded blocks.
#@param path str Existing regular runtime library path.
#@return str Lowercase SHA-256 of the complete file.
#@effect Reads the file and closes its handle on success or failure.
def digest(path):
    value=hashlib.sha256()
    with open(path,'rb') as source:
        while True:
            chunk=source.read(1048576)
            if not chunk:
                break
            value.update(chunk)
    return value.hexdigest()


# Export only the admitted CentOS packages' native runtime/link files into a new directory.
#@param none Parses the new output directory from the command line.
#@return None No result; prints PASS only after every selected file has a recorded digest.
#@error Raises for another OS/libc/package version, an occupied output or incomplete libraries.
#@effect Queries RPM ownership, reads package files and creates the owned output and manifest.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output')
    args=parser.parse_args()
    if not os.path.isfile('/etc/centos-release'):
        raise ValueError('CentOS 7 export host is required')
    libc=subprocess.check_output(['getconf','GNU_LIBC_VERSION']).decode('ascii').strip()
    if libc!='glibc 2.17':
        raise ValueError('glibc 2.17 export host is required')
    expected={'glibc.x86_64':'glibc-2.17-317.el7.x86_64',
              'glibc-devel.x86_64':'glibc-devel-2.17-317.el7.x86_64',
              'libgcc.x86_64':'libgcc-4.8.5-44.el7.x86_64',
              'libstdc++.x86_64':'libstdc++-4.8.5-44.el7.x86_64'}
    for package,version in expected.items():
        actual=subprocess.check_output(['rpm','-q',package]).decode('ascii').strip()
        if actual!=version:
            raise ValueError('export package version differs: '+package)
    if os.path.lexists(args.output):
        raise ValueError('runtime output already exists')
    os.mkdir(args.output)
    directory=os.path.join(args.output,'lib64')
    os.mkdir(directory)
    records=[]
    selected=set()
    for package in sorted(expected):
        paths=subprocess.check_output(['rpm','-ql',package]).decode('ascii').splitlines()
        for path in paths:
            if os.path.dirname(path) not in ('/usr/lib64','/lib64') \
                    or not os.path.isfile(path) or path in selected:
                continue
            real=os.path.realpath(path)
            if os.path.dirname(real) not in ('/usr/lib64','/lib64'):
                raise ValueError('package library leaves its native closure: '+path)
            selected.add(path)
            leaf=os.path.basename(path)
            destination=os.path.join(directory,leaf)
            shutil.copyfile(path,destination)
            mode=os.stat(path).st_mode&0o777
            os.chmod(destination,mode)
            records.append({'file':'lib64/'+leaf,'sha256':digest(destination),
                            'source':path,'package':expected[package],'mode':mode})
    names=set(record['file'] for record in records)
    required=set('lib64/'+name for name in ('libc-2.17.so','ld-2.17.so','libc_nonshared.a','libpthread_nonshared.a'))
    if not required<=names:
        raise ValueError('exported C7 native closure is incomplete')
    with open(os.path.join(args.output,'runtime-inputs.json'),'w') as output:
        json.dump({'schema':'yaca-centos7-runtime-v1','libc':libc,'packages':expected,
                   'files':records},output,indent=2)
        output.write('\n')
    print('centos-runtime-export=PASS files='+str(len(records)))


if __name__=='__main__':
    main()
