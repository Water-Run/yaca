#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-05
# File: linux_full_staging_test.py
# Description: Prove compiler staging retains headers and static archives independently of source directory names.

import importlib.util
import pathlib
import json
import subprocess
import tarfile
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('prepare_linux_full',ROOT/'.tools/qualification/prepare_linux_full.py')
STAGING=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STAGING)


#@class CompilerTreeTest Owns disposable source trees that distinguish development and runtime payloads.
#@field root Path Temporary parent removed after each case.
class CompilerTreeTest(unittest.TestCase):
    # Allocate a fresh tree and register its removal.
    #@param self CompilerTreeTest Fixture owner.
    #@return None No value; stores the temporary root on self.
    #@effect Creates only the test-owned temporary directory.
    def setUp(self):
        temporary=tempfile.TemporaryDirectory(prefix='linux staging ')
        self.addCleanup(temporary.cleanup)
        self.root=pathlib.Path(temporary.name)

    # Preserve headers and archives even when the input directory contains no compiler keyword.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions verify headers, sysroot headers and static link archives survive.
    #@effect Writes a disposable SDK and copies it through the production compiler staging path.
    def test_compiler_headers_and_static_libraries_are_preserved(self):
        source=self.root/'prefix'
        for name in ('include/stdio.h','lib/libgcc.a','sysroot/usr/include/features.h'):
            path=source/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b'compiler fixture')
        STAGING.copy_tree(source,self.root/'copied',compiler=True)
        for name in ('include/stdio.h','lib/libgcc.a','sysroot/usr/include/features.h'):
            self.assertEqual((self.root/'copied'/name).read_bytes(),b'compiler fixture')

    # Select runtime pruning explicitly even when the parent path has compiler in its name.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions verify path spelling does not retain unwanted runtime development inputs.
    #@effect Creates and copies a disposable runtime tree.
    def test_runtime_pruning_does_not_depend_on_the_directory_name(self):
        source=self.root/'compiler-parent/runtime'
        (source/'include').mkdir(parents=True)
        (source/'include/header.h').write_bytes(b'header fixture')
        (source/'library.a').write_bytes(b'archive fixture')
        (source/'program').write_bytes(b'runtime fixture')
        STAGING.copy_tree(source,self.root/'copied')
        self.assertFalse((self.root/'copied/include').exists())
        self.assertFalse((self.root/'copied/library.a').exists())
        self.assertEqual((self.root/'copied/program').read_bytes(),b'runtime fixture')

    # Require both a tool's source and its native dependency in the generated corresponding-source bundle.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions inspect actual tar members and reject optional source omissions.
    #@effect Creates only disposable source files and a source archive in the fixture root.
    def test_source_bundle_contains_every_selected_dependency(self):
        admitted={}
        for name in ('git-source.tar.xz','tls-source.tar.bz2'):
            path=self.root/name
            path.write_bytes(name.encode())
            admitted[name]={'path':path,'sha256':STAGING.sha256(path)}
        archive=self.root/'closure.tar.gz'
        digest=STAGING.bundle_sources(archive,tuple(admitted),admitted)
        self.assertEqual(digest,STAGING.sha256(archive))
        with tarfile.open(archive) as source:
            for name in admitted:
                self.assertEqual(source.extractfile(name).read(),name.encode())
            self.assertIn('yaca-build/build_linux_git_https.sh',source.getnames())

    # Fail before archive creation when a corresponding dependency is missing or differs from its pin.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions prove an incomplete or changed source closure cannot be published.
    #@effect Writes and mutates one disposable source fixture; rejected output paths remain absent.
    def test_missing_or_changed_source_is_not_skipped(self):
        path=self.root/'source.tar.xz'
        path.write_bytes(b'original source')
        admitted={'source.tar.xz':{'path':path,'sha256':STAGING.sha256(path)}}
        with self.assertRaises(ValueError):
            STAGING.bundle_sources(self.root/'missing.tar.gz',('source.tar.xz','dependency.tar.xz'),admitted)
        self.assertFalse((self.root/'missing.tar.gz').exists())
        path.write_bytes(b'changed source')
        with self.assertRaises(ValueError):
            STAGING.bundle_sources(self.root/'changed.tar.gz',('source.tar.xz',),admitted)
        self.assertFalse((self.root/'changed.tar.gz').exists())

    # Refuse outside and dangling links instead of shipping unrelated host bytes or silently losing a dependency.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions require both invalid closures to stop with the links retained for diagnosis.
    #@effect Creates only test-owned files and symbolic links.
    def test_runtime_links_remain_inside_the_closure(self):
        root=self.root/'tools'
        root.mkdir()
        outside=self.root/'host-library'
        outside.write_bytes(b'host-only library')
        link=root/'runtime-library'
        link.symlink_to(outside)
        with self.assertRaises(ValueError):
            STAGING.materialize_links(root)
        self.assertTrue(link.is_symlink())
        link.unlink()
        link.symlink_to(root/'absent-library')
        with self.assertRaises(FileNotFoundError):
            STAGING.materialize_links(root)
        self.assertTrue(link.is_symlink())

    # Construct a small hashed C7 library export without using or claiming real target artifacts.
    #@param self CompilerTreeTest Fixture owner.
    #@return Path Disposable runtime input directory with the four required synthetic libraries.
    #@effect Creates only fixture files and their source-binding manifest.
    def runtime_fixture(self):
        root=self.root/'c7-runtime'
        (root/'lib64').mkdir(parents=True)
        records=[]
        for name in ('libc-2.17.so','ld-2.17.so','libc_nonshared.a','libpthread_nonshared.a'):
            path=root/'lib64'/name
            path.write_bytes(('fixture '+name).encode())
            records.append({'file':'lib64/'+name,'sha256':STAGING.sha256(path)})
        (root/'runtime-inputs.json').write_text(json.dumps({'schema':'yaca-centos7-runtime-v1',
                                                         'libc':'glibc 2.17','files':records}))
        return root

    # Populate the missing loader and link libraries into all SDK lookup locations.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions verify the exact admitted bytes survive all three copies.
    #@effect Copies only the synthetic runtime into a disposable compiler tree.
    def test_sysroot_completion_carries_loader_and_nonshared_archives(self):
        runtime=self.runtime_fixture()
        compiler=self.root/'compiler'
        (compiler/'x86_64-pc-linux-gnu/lib').mkdir(parents=True)
        STAGING.complete_compiler_sysroot(compiler,runtime)
        for directory in ('sysroot/usr/lib64','sysroot/lib64','x86_64-pc-linux-gnu/lib'):
            for path in (runtime/'lib64').iterdir():
                self.assertEqual((compiler/directory/path.name).read_bytes(),path.read_bytes())

    # Reject a changed C7 library before it can populate the SDK.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions require hash drift to stop before copying any sysroot files.
    #@effect Mutates one synthetic runtime file; output remains empty after rejection.
    def test_changed_sysroot_input_is_refused(self):
        runtime=self.runtime_fixture()
        (runtime/'lib64/ld-2.17.so').write_bytes(b'changed loader')
        compiler=self.root/'compiler'
        (compiler/'x86_64-pc-linux-gnu/lib').mkdir(parents=True)
        with self.assertRaises(ValueError):
            STAGING.complete_compiler_sysroot(compiler,runtime)
        self.assertFalse((compiler/'sysroot').exists())

    # Exercise the generated launcher's quoting and SDK selection from a path containing spaces.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions check exact default flags and preservation of a user argument with spaces.
    #@effect Executes only a print-only shell fixture under the owned temporary compiler directory.
    def test_compiler_launcher_selects_adjacent_sdk_with_spaces(self):
        compiler=self.root/'portable SDK'
        (compiler/'bin').mkdir(parents=True)
        for name in ('gcc','g++'):
            path=compiler/'bin'/name
            path.write_text('#!/bin/sh\n# Author: WaterRun\n# Date: 2026-10-05\n# File: '+name+
                            '\n# Description: Print-only compiler fixture records each received argument.\n'
                            'for argument do printf "%s\\n" "$argument"; done\n')
            path.chmod(0o755)
        STAGING.install_compiler_launchers(compiler)
        output=subprocess.check_output([str(compiler/'bin/gcc'),'file name.c'],text=True)
        self.assertEqual(output.splitlines(),['--sysroot='+str(compiler/'sysroot'),
                                             '-static-libgcc','-static-libstdc++','file name.c'])

    # Materialize a valid SDK directory alias while retaining every regular header byte.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions require a regular copied directory and no remaining alias link.
    #@effect Creates and materializes only the temporary SDK fixture.
    def test_directory_alias_retains_headers(self):
        root=self.root/'tools'
        (root/'headers/nested').mkdir(parents=True)
        (root/'headers/nested/header.h').write_bytes(b'portable header')
        alias=root/'include'
        alias.symlink_to('headers',target_is_directory=True)
        STAGING.materialize_links(root)
        self.assertFalse(alias.is_symlink())
        self.assertEqual((alias/'nested/header.h').read_bytes(),b'portable header')

    # Refuse recursive aliases and nested links outside the source closure without publishing partial replacements.
    #@param self CompilerTreeTest Fixture owner.
    #@return None Assertions require both invalid directory aliases to remain unchanged after rejection.
    #@effect Creates only test-owned directories, files and symlinks.
    def test_cyclic_and_escaping_directory_aliases_are_refused(self):
        root=self.root/'tools'
        root.mkdir()
        alias=root/'cycle'
        alias.symlink_to(root,target_is_directory=True)
        with self.assertRaises(ValueError):
            STAGING.materialize_links(root)
        self.assertTrue(alias.is_symlink())
        alias.unlink()
        (root/'headers').mkdir()
        outside=self.root/'private-host-file'
        outside.write_bytes(b'outside fixture')
        (root/'headers/link').symlink_to(outside)
        alias.symlink_to('headers',target_is_directory=True)
        with self.assertRaises(ValueError):
            STAGING.materialize_links(root)
        self.assertTrue(alias.is_symlink())


if __name__=='__main__':
    unittest.main()
