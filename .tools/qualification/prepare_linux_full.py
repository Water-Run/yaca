#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: prepare_linux_full.py
# Description: Stages the Linux full toolbox with compiler inputs, Git HTTP/Perl helpers and exact per-tool source closures.

"""Stage the portable Linux full bundled software from verified build outputs.

This is a build-host utility, never a yaca runtime dependency. It recombines
the std staging (python2, ssh, curl, 7zz) with the six full-only closures
built inside the CentOS 7 container (busybox, jq, sqlite, the GCC 13.5
toolchain, python 3.14.7 and git 2.55.0), writes tools/INDEX.txt for model
context, and records the exact SHA-256 manifest the edition packager
consumes. Git and compiler paths are explicit; source archives must match the
maintained pins, and no missing dependency is silently omitted.
"""

import argparse
import gzip
import hashlib
import json
import pathlib
import re
import shutil
import tarfile
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]

SOURCE_PROFILES = {
    "busybox": ("busybox-1.37.0.tar.bz2",),
    "jq": ("jq-1.8.2.tar.gz", "onig-6.9.10.tar.gz"),
    "sqlite": ("sqlite-autoconf-3530400.tar.gz", "sqlite-src-3530400.zip"),
    "compiler": ("gcc-13.5.0.tar.xz", "binutils-2.47.tar.xz", "make-4.4.1.tar.gz",
                 "gmp-6.3.0.tar.xz", "mpfr-4.2.1.tar.xz", "mpc-1.3.1.tar.gz",
                 "glibc-2.17-317.el7.src.rpm", "kernel-3.10.0-1160.el7.src.rpm",
                 "gcc-4.8.5-44.el7.src.rpm"),
    "python3": ("Python-3.14.7.tgz", "openssl-3.0.16.tar.gz", "libffi-3.4.6.tar.gz",
                "sqlite-autoconf-3530400.tar.gz"),
    "git": ("git-2.55.0.tar.xz", "perl-5.42.3.tar.xz", "libxcrypt-4.4.38.tar.xz", "curl-8.21.0.tar.xz",
            "mbedtls-3.6.7.tar.bz2", "expat-2.8.2.tar.gz", "gcc-13.5.0.tar.xz"),
}


# Computes a SHA-256 digest for the staged payload.
#@param path Path|str Input file or package path under inspection.
#@return str digest Hexadecimal SHA-256 digest of the supplied data.
def sha256(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open("rb") as source:
        # Reads the next block of a source file for SHA-256 hashing.
        #@param none No arguments.
        #@return bytes Up to one MiB from the source, or empty at EOF.
        for chunk in iter(lambda: source.read(1048576), b""):
            value.update(chunk)
    return value.hexdigest()


# Copies a file granting execute permission to every derived artifact.
#@param source Path|str File to copy.
#@param destination Path|str Destination path inside the staged tree.
#@return void No value; copies exactly one file with the portable mode.
def copy_program(source, destination):
    shutil.copyfile(source, destination)
    destination.chmod(0o755)


# Copy a runtime or compiler tree, preserving the compiler's headers and static link libraries.
#@param source Path|str Source directory to copy.
#@param destination Path|str Destination directory inside the staged tree.
#@param compiler bool True for a development compiler/sysroot; false prunes runtime-only development payload.
#@return void No value; copies the selected tree without deleting or modifying the source.
#@effect Creates the destination tree and preserves compiler include directories and static archives.
def copy_tree(source, destination, compiler=False):
    prune = (shutil.ignore_patterns("__pycache__", "*.pyc", "test", "tests")
             if compiler
             else shutil.ignore_patterns("__pycache__", "test", "tests", "*.a",
                                         "include", "*.pyc", "idle", "tcl"))
    shutil.copytree(source, destination, symlinks=True,
                    # Prunes development payloads per tree kind; the compiler keeps its
                    # static archives because libgcc.a is required at every link.
                    #@param directory str Candidate directory name under the copy root.
                    #@param entries list Directory entries within the visited directory.
                    #@return list Entries excluded from the copied tree.
                    ignore=prune)


# Admit every full-only source dependency from frozen locks before staging starts.
#@param caches list[Path] Explicit directories searched in order for source archives.
#@return dict Verified archive metadata indexed by basename, including path, URL and SHA-256.
#@error Raises on missing pins, changed archives, conflicting records or source symlinks.
#@effect Reads maintained locks and hashes every source in the full tool profiles.
def admit_sources(caches):
    lock=json.loads((REPO/'release/full-tool-sources.lock.json').read_text())
    records=lock['sources']+lock.get('git_runtime_sources',[])
    records+= [
        {'file':'curl-8.21.0.tar.xz','sha256':'aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6','url':'https://curl.se/download/curl-8.21.0.tar.xz'},
        {'file':'mbedtls-3.6.7.tar.bz2','sha256':'a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6','url':'https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2'},
        {'file':'expat-2.8.2.tar.gz','sha256':'ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c','url':'https://github.com/libexpat/libexpat/releases/download/R_2_8_2/expat-2.8.2.tar.gz'},
    ]
    wanted={name for profile in SOURCE_PROFILES.values() for name in profile}
    admitted={}
    for record in records:
        name=record['file']
        if name not in wanted:
            continue
        if name in admitted and admitted[name]['sha256']!=record['sha256']:
            raise ValueError('conflicting source pin: '+name)
        candidates=[cache/name for cache in caches if (cache/name).is_file()]
        if not candidates or candidates[0].is_symlink() or sha256(candidates[0])!=record['sha256']:
            raise ValueError('source is absent or differs from its pin: '+name)
        if not record['url'].startswith('https://'):
            raise ValueError('source URL must use HTTPS: '+name)
        admitted[name]={'path':candidates[0],'sha256':record['sha256'],'url':record['url']}
    if wanted!=set(admitted):
        raise ValueError('missing source pins: '+', '.join(sorted(wanted-set(admitted))))
    return admitted


# Write the complete corresponding-source profile for a tool without optional omissions.
#@param destination Path New tar.gz path; existing files are refused.
#@param names tuple[str]|list[str] Exact required source basenames for this tool and its native dependencies.
#@param admitted dict Verified paths and SHA-256 values returned by admit_sources.
#@return str SHA-256 of the complete generated source bundle.
#@error Raises before creation on missing/changed sources, or on archive I/O errors.
#@effect Reads selected sources and maintained build/staging recipes; creates only the new archive.
def bundle_sources(destination,names,admitted):
    selected=[]
    for name in names:
        record=admitted.get(name)
        if not record or record['path'].is_symlink() or sha256(record['path'])!=record['sha256']:
            raise ValueError('corresponding source is absent or changed: '+name)
        selected.append((name,record['path']))
    for relative in ('.tools/qualification/prepare_linux_full.py',
                     '.tools/qualification/build_linux_git_https.sh',
                     '.tools/qualification/build_linux_perl.sh',
                     '.tools/qualification/export_centos_runtime.py',
                     'release/full-tool-sources.lock.json','release/dependencies.lock'):
        selected.append(('yaca-build/'+pathlib.Path(relative).name,REPO/relative))
    with destination.open('xb') as output,gzip.GzipFile(fileobj=output,mode='wb',mtime=946684800) as compressed:
        with tarfile.open(fileobj=compressed,mode='w') as archive:
            for name,path in selected:
                info=tarfile.TarInfo(name)
                info.size=path.stat().st_size
                info.mode=0o644
                info.mtime=946684800
                with path.open('rb') as source:
                    archive.addfile(info,source)
    return sha256(destination)


# Copy an unmodified license from one admitted upstream archive.
#@param admitted dict Verified source metadata indexed by basename.
#@param name str Archive basename that owns the license.
#@param member str Exact regular member path inside that archive.
#@param destination Path License path below the owned staging tree.
#@return None No result; malformed members and I/O failures raise.
#@effect Reads bounded license bytes and creates the selected destination file.
def copy_license(admitted,name,member,destination):
    with tarfile.open(admitted[name]['path']) as archive:
        info=archive.getmember(member)
        if not info.isfile() or not 100<=info.size<=131072:
            raise ValueError('license member is not a bounded regular file: '+member)
        with archive.extractfile(info) as source:
            destination.write_bytes(source.read())


# Materialize file symlinks while refusing missing targets or references outside the owned tools tree.
#@param root Path Owned staging/tools directory.
#@return None No result; invalid or cyclic links raise before replacement.
#@error Refuses unresolved, escaping or cyclic links instead of silently dropping dependencies.
#@effect Replaces only owned symlinks with the target bytes and permission mode.
def materialize_links(root):
    root=root.resolve()
    # Copy a confined directory alias into regular files without following an escaping or cyclic nested link.
    #@param source Path Resolved directory whose bytes remain within root.
    #@param destination Path Existing owned temporary directory receiving the copy.
    #@param ancestors set[Path] Resolved directory ancestry used to reject cycles.
    #@return None No result; all copied descendants are regular files/directories.
    #@error Raises for escaping, cyclic or non-file/directory members before publishing the alias replacement.
    #@effect Creates only children of destination; reads source files without modifying them.
    def copy_directory(source,destination,ancestors):
        for item in source.iterdir():
            resolved=item.resolve(strict=True)
            if not resolved.is_relative_to(root):
                raise ValueError('directory alias leaves its closure: '+str(item))
            target=destination/item.name
            if resolved.is_dir():
                if resolved in ancestors:
                    raise ValueError('cyclic directory alias: '+str(item))
                target.mkdir()
                copy_directory(resolved,target,ancestors|{resolved})
            elif resolved.is_file():
                shutil.copy2(resolved,target)
            else:
                raise ValueError('directory alias contains a special file: '+str(item))
    for link in list(root.rglob('*')):
        if link.is_symlink():
            target=link.resolve(strict=True)
            if not target.is_relative_to(root):
                raise ValueError('tool link leaves its closure: '+str(link))
            if target.is_dir():
                if link.is_relative_to(target):
                    raise ValueError('tool directory alias contains itself: '+str(link))
                temporary=pathlib.Path(tempfile.mkdtemp(prefix='.materializing-',dir=link.parent))
                try:
                    copy_directory(target,temporary,{target})
                    link.unlink()
                    temporary.rename(link)
                finally:
                    if temporary.exists():
                        shutil.rmtree(temporary)
                continue
            if not target.is_file():
                raise ValueError('tool link is not a regular file: '+str(link))
            data=target.read_bytes()
            mode=target.stat().st_mode&0o777
            link.unlink()
            link.write_bytes(data)
            link.chmod(mode)


# Complete the SDK's runtime link inputs from a hashed CentOS 7 package export.
#@param root Path Owned staged compiler tree containing the native target libraries and sysroot.
#@param runtime Path Explicit output of export_centos_runtime.py with its per-file/package manifest.
#@return None No result; missing native library inputs or conflicting SDK files raise.
#@effect Copies verified C7 libraries into owned sysroot and target link directories; original build inputs remain untouched.
def complete_compiler_sysroot(root,runtime):
    libraries=root/'x86_64-pc-linux-gnu/lib'
    if not libraries.is_dir():
        raise ValueError('compiler target runtime libraries are missing')
    manifest=json.loads((runtime/'runtime-inputs.json').read_text())
    if manifest.get('schema')!='yaca-centos7-runtime-v1' or manifest.get('libc')!='glibc 2.17':
        raise ValueError('C7 compiler runtime input manifest is invalid')
    selected=[]
    seen=set()
    for record in manifest['files']:
        relative=pathlib.PurePosixPath(record['file'])
        if len(relative.parts)!=2 or relative.parts[0]!='lib64' or relative.name in seen:
            raise ValueError('invalid or duplicate C7 library path')
        source=runtime/record['file']
        if source.is_symlink() or not source.resolve(strict=True).is_relative_to(runtime.resolve()) \
                or sha256(source)!=record['sha256']:
            raise ValueError('C7 library differs from its recorded bytes: '+record['file'])
        selected.append((source,relative.name))
        seen.add(relative.name)
    required={'libc-2.17.so','ld-2.17.so','libc_nonshared.a','libpthread_nonshared.a'}
    if not required<=seen:
        raise ValueError('C7 compiler runtime closure is incomplete')
    for directory in (root/'sysroot/usr/lib64',root/'sysroot/lib64',libraries):
        directory.mkdir(parents=True,exist_ok=True)
        for source,name in selected:
            destination=directory/name
            if destination.is_symlink():
                destination.unlink()
            shutil.copy2(source,destination)
    shutil.copyfile(runtime/'runtime-inputs.json',root/'CENTOS-RUNTIME-INPUTS.json')


# Install compiler launchers that bind default headers and link inputs to the adjacent glibc 2.17 SDK.
#@param root Path Owned staged compiler tree with materialized regular files and complete sysroot.
#@return None No result; missing core compiler commands or occupied backup names raise.
#@effect Renames owned compiler entry binaries and writes executable POSIX launchers; explicit later user flags still override defaults.
def install_compiler_launchers(root):
    commands=[]
    for command in (root/'bin').iterdir():
        if command.name in ('gcc','g++','cc','c++','cpp') or re.fullmatch(
                r'x86_64-pc-linux-gnu-(gcc|g\+\+|cc|c\+\+|cpp)(-[0-9.]+)?',command.name):
            commands.append(command)
    if not {'gcc','g++'}<={path.name for path in commands}:
        raise ValueError('compiler C/C++ entry points are missing')
    for command in commands:
        native=command.with_name(command.name+'.real')
        if native.exists():
            raise ValueError('compiler native backup already exists')
        command.rename(native)
        text='''#!/bin/sh
# Author: WaterRun
# Date: 2026-10-05
# File: NAME
# Description: Run the adjacent compiler with its portable headers, link libraries and C++ runtime.
YACA_COMPILER_ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd -P) || exit 1
YACA_COMPILER_LIBRARIES="$YACA_COMPILER_ROOT/lib64"
if [ -n "${LD_LIBRARY_PATH:-}" ]; then
  YACA_COMPILER_LIBRARIES="$YACA_COMPILER_LIBRARIES:$LD_LIBRARY_PATH"
fi
export LD_LIBRARY_PATH="$YACA_COMPILER_LIBRARIES"
exec "$YACA_COMPILER_ROOT/bin/NAME.real" --sysroot="$YACA_COMPILER_ROOT/sysroot" -static-libgcc -static-libstdc++ "$@"
'''
        command.write_text(text.replace('NAME',command.name),encoding='utf-8')
        command.chmod(0o755)


# Runs the prepare linux full command and reports its status.
#@param none No arguments; all paths arrive through sys.argv.
#@return None result No value; writes the staged tree, INDEX.txt and tool-inputs.json.
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('std_staged',type=pathlib.Path)
    parser.add_argument('toolchain',type=pathlib.Path)
    parser.add_argument('output',type=pathlib.Path)
    parser.add_argument('--git-prefix',required=True,type=pathlib.Path)
    parser.add_argument('--compiler-prefix',required=True,type=pathlib.Path)
    parser.add_argument('--source-cache',required=True,type=pathlib.Path)
    parser.add_argument('--centos-runtime',required=True,type=pathlib.Path)
    args=parser.parse_args()
    std_staged,toolchain,output=args.std_staged,args.toolchain.resolve(),args.output
    if output.exists():
        raise SystemExit("staging output already exists")
    admitted=admit_sources([args.source_cache,REPO/'out/qualification/sources'])
    std=json.loads((std_staged/'tool-inputs.json').read_text())
    if std.get('schema')!='yaca-tool-inputs-v1' or std.get('target')!='linux-x86_64' \
            or {item['id'] for item in std['tools']}!={'python2','ssh','curl','archive'}:
        raise ValueError('Linux std closure is incomplete')
    git_summary=(args.git_prefix.parent/'build-summary.txt').read_text()
    for entry in ('bin/git','bin/perl','libexec/git-core/git-remote-http','libexec/git-core/git-remote-https'):
        if not (args.git_prefix/entry).is_file():
            raise ValueError('Git runtime helper is missing: '+entry)
    if 'status=PASS\n' not in git_summary or sha256(args.git_prefix/'bin/git') not in git_summary:
        raise ValueError('Git build evidence does not bind this runtime')
    output.mkdir(parents=True)
    shutil.copytree(std_staged / "tools", output / "tools")
    shutil.copytree(std_staged / "sources", output / "sources")

    build = toolchain.parent / "build"
    programs = {
        "busybox": (toolchain / "bb137/busybox-1.37.0/busybox", "busybox", "1.37.0"),
        "jq": (build / "jq-root/bin/jq", "jq", "1.8.2"),
    }
    for name, (source, leaf, _version) in programs.items():
        (output / "tools" / name).mkdir(exist_ok=True)
        copy_program(source, output / "tools" / name / leaf)
    shutil.copyfile(toolchain / "bb137/busybox-1.37.0/LICENSE", output / "tools/busybox/LICENSE")
    shutil.copyfile(build / "jq-1.8.2/COPYING", output / "tools/jq/COPYING")
    shutil.copyfile(build / "onig-6.9.10/COPYING", output / "tools/jq/COPYING.Oniguruma")

    (output / "tools/sqlite").mkdir(exist_ok=True)
    for name in ("sqlite3", "sqldiff"):
        copy_program(build / "sqlite-root/bin" / name, output / "tools/sqlite" / name)
    shutil.copyfile(build / "sqlite-src-3530400/LICENSE.md", output / "tools/sqlite/LICENSE.md")

    (output / "tools/compiler").mkdir()
    for name in ("bin", "include", "libexec", "lib", "lib64", "x86_64-pc-linux-gnu", "sysroot", "share"):
        source = args.compiler_prefix / name
        if source.is_dir():
            copy_tree(source, output / "tools/compiler" / name, compiler=True)

    copy_tree(toolchain / "py314-root-new/py314-root", output / "tools/python3")
    shutil.copyfile(toolchain / "py314/Python-3.14.7/LICENSE", output / "tools/python3/LICENSE")
    shutil.copyfile(toolchain/'ssl/openssl-3.0.16/LICENSE.txt',output/'tools/python3/LICENSE.OpenSSL')
    copy_license(admitted,'libffi-3.4.6.tar.gz','libffi-3.4.6/LICENSE',output/'tools/python3/LICENSE.libffi')

    # git's libexec hardlink farm shares one binary; preserving links keeps the tree at one copy.
    shutil.copytree(args.git_prefix,output/'tools/git',symlinks=True)
    copy_license(admitted,'curl-8.21.0.tar.xz','curl-8.21.0/COPYING',output/'tools/git/COPYING.curl')
    copy_license(admitted,'mbedtls-3.6.7.tar.bz2','mbedtls-3.6.7/LICENSE',output/'tools/git/LICENSE.MbedTLS')
    copy_license(admitted,'expat-2.8.2.tar.gz','expat-2.8.2/COPYING',output/'tools/git/COPYING.Expat')
    copy_license(admitted,'libxcrypt-4.4.38.tar.xz','libxcrypt-4.4.38/COPYING.LIB',output/'tools/git/COPYING.libxcrypt')
    copy_license(admitted,'libxcrypt-4.4.38.tar.xz','libxcrypt-4.4.38/LICENSING',output/'tools/git/LICENSING.libxcrypt')

    # The packager rejects symlinks; materialize every link as a real copy.
    complete_compiler_sysroot(output/'tools/compiler',args.centos_runtime)
    materialize_links(output/'tools')
    install_compiler_launchers(output/'tools/compiler')

    # git's libexec farm ships one binary under many names; hardlink byte-identical
    # files so the staged tree (and any zip preserving links) stays near one copy.
    unique = {}
    for path in sorted((output / "tools/git/libexec/git-core").iterdir()):
        if path.is_file() and not path.is_symlink():
            digest = sha256(path)
            master = unique.get(digest)
            if master is None:
                unique[digest] = path
            else:
                path.unlink()
                path.hardlink_to(master)

    for name,member,leaf in (
            ('gcc-13.5.0.tar.xz','gcc-13.5.0/COPYING3','COPYING.GPL3'),
            ('gcc-13.5.0.tar.xz','gcc-13.5.0/COPYING','COPYING.GPL2'),
            ('gcc-13.5.0.tar.xz','gcc-13.5.0/COPYING.LIB','COPYING.LGPL2.1'),
            ('gcc-13.5.0.tar.xz','gcc-13.5.0/COPYING.RUNTIME','COPYING.RUNTIME'),
            ('mpfr-4.2.1.tar.xz','mpfr-4.2.1/COPYING.LESSER','COPYING.LGPL3')):
        copy_license(admitted,name,member,output/'tools/compiler'/leaf)

    index_lines = [
        "# yaca bundled software index",
        "# name | summary | manual URL | notes",
        "# Bundled programs are not tool calls; invoke them through exec or the lua tool.",
        "python2|Python 2 interpreter and standard library, no pip|https://docs.python.org/2/|runs via exec or lua",
        "ssh|PuTTY 0.85 portable CLI: plink, pscp, psftp|https://the.earth.li/~sgtatham/putty/0.85/htmldoc/|supply a verified -hostkey",
        "curl|HTTP and HTTPS client with its own CA bundle|https://curl.se/docs/|pass --cacert tools/curl/cacert.pem",
        "archive|7-Zip console archiver|https://github.com/ip7z/7zip|7zz handles 7z/zip/tar and more",
        "busybox|399-applet multi-call binary: awk, sed, grep, find, diff and more|https://busybox.net/|invoke as busybox <applet>",
        "jq|JSON command-line processor with regex|https://jqlang.github.io/jq/manual/|statically linked",
        "sqlite|sqlite3 and sqldiff command-line tools|https://sqlite.org/cli.html|not the yaca data store",
        "compiler|GCC 13.5.0, Binutils 2.47 and Make 4.4.1 with glibc 2.17 sysroot|https://gcc.gnu.org/onlinedocs/|set PATH to tools/compiler/bin; launchers select the adjacent SDK and static C++ runtime",
        "python3|Python 3.14.7 with OpenSSL 3.0.16, sqlite3 and ctypes|https://docs.python.org/3.14/|built on the CentOS 7 baseline",
        "git|Git 2.55.0 with HTTP/TLS and adjacent Perl|https://git-scm.com/docs/|use tools/curl/cacert.pem for HTTPS; CLI helpers",
    ]
    (output / "tools/INDEX.txt").write_text("\n".join(index_lines) + "\n", encoding="utf-8")

    specifications = [
        ("busybox", "busybox", "1.37.0", ["busybox"], "GPL-2.0-only", ["LICENSE"]),
        ("jq", "jq", "1.8.2", ["jq"], "MIT AND BSD-2-Clause", ["COPYING","COPYING.Oniguruma"]),
        ("sqlite", "sqlite", "3.53.4", ["sqlite3", "sqldiff"],
         "LicenseRef-SQLite-Public-Domain", ["LICENSE.md"]),
        ("compiler", "compiler", "GCC-13.5.0_Binutils-2.47_Make-4.4.1", ["bin/gcc","bin/g++","bin/ld","bin/make"],
         "GPL-3.0-or-later AND LGPL-2.1-or-later AND LGPL-3.0-or-later AND GPL-3.0-or-later WITH GCC-exception-3.1",
         ["COPYING.GPL3","COPYING.GPL2","COPYING.LGPL2.1","COPYING.LGPL3","COPYING.RUNTIME"]),
        ("python3", "python3", "3.14.7", ["bin/python3.14"], "Python-2.0.1 AND Apache-2.0 AND MIT",
         ["LICENSE","LICENSE.OpenSSL","LICENSE.libffi"]),
        ("git", "git", "2.55.0", ["bin/git","bin/perl","libexec/git-core/git-remote-http","libexec/git-core/git-remote-https"],
         "GPL-2.0-only AND (Artistic-1.0-Perl OR GPL-1.0-or-later) AND LGPL-2.1-or-later AND curl AND Apache-2.0 AND MIT",
         ["COPYING","COPYING.Perl","ARTISTIC.Perl","COPYING.libxcrypt","LICENSING.libxcrypt","COPYING.curl","LICENSE.MbedTLS","COPYING.Expat"]),
    ]
    records = list(std['tools'])
    for identifier, directory, version, entries, license_id, notices in specifications:
        prefix = "tools/" + directory + "/"
        for entry in entries+notices:
            if not (output/'tools'/directory/entry).is_file():
                raise ValueError('entry or license is missing: '+prefix+entry)
        payload = []
        for path in sorted((output / "tools" / directory).rglob("*")):
            if path.is_file():
                payload.append({"source": str(path.relative_to(output)),
                                "destination": str(path.relative_to(output)),
                                "sha256": sha256(path),
                                "executable": bool(path.stat().st_mode&0o111)})
        source_name=identifier+'-source-closure.tar.gz'
        source_digest=bundle_sources(output/'sources'/source_name,SOURCE_PROFILES[identifier],admitted)
        records.append({"id": identifier, "version": version,
                        "entry_points": [prefix + name for name in entries],
                        "license_id": license_id,
                        "license_files": [prefix + name for name in notices],
                        "source_url": admitted[SOURCE_PROFILES[identifier][0]]['url'],
                        "source_archive": {"source": "sources/"+source_name, "sha256": source_digest},
                        "files": payload})
    (output / "tool-inputs.json").write_text(
        json.dumps({"schema": "yaca-tool-inputs-v1", "target": "linux-x86_64",
                    "tools": records}, indent=2) + "\n", encoding="utf-8")
    print("linux-full-staging=PASS tools=10 index=written target-qualification=pending")


if __name__ == "__main__":
    main()
