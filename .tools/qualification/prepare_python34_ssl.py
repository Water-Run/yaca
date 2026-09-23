#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: prepare_python34_ssl.py
# Description: Generate CPython 3.4's Win32 OpenSSL inputs on the source preparation host.

"""Generate CPython 3.4's Win32 OpenSSL inputs on the source preparation host.

Use the upstream portable C implementation so the build needs neither a Windows
Perl installation nor assembler executables. This changes build inputs only.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess


# Stages pinned compatibility inputs in an isolated output root.
#@param root Path Isolated proof or staging root.
#@return None result No value; stages SSL inputs for portable Python 3.4.
def prepare(root):
    assert 'OpenSSL 1.0.2k' in (root / 'crypto/opensslv.h').read_text()
    subprocess.run(['perl', 'Configure', 'VC-WIN32', 'no-asm', 'no-idea',
                    'no-mdc2', 'no-rc5'], cwd=root, check=True)
    with (root / 'MINFO').open('wb') as output:
        subprocess.run(['perl', 'util/mkfiles.pl'], cwd=root, stdout=output, check=True)
    generator = (root / 'util/mk1mf.pl').read_text()
    original = 'if (-f "${_}.c")'
    assert generator.count(original) == 1
    generator = generator.replace(original,
        'my $host_source = "${_}.c"; $host_source =~ s{\\\\}{/}g;\n\t\tif (-f $host_source)')
    generator = generator.replace('scalar gmtime()',
        'scalar gmtime($ENV{SOURCE_DATE_EPOCH} || 1790035200)')
    (root / 'util/yaca-mk1mf.pl').write_text(generator)
    result = subprocess.run(['perl', 'util/yaca-mk1mf.pl', 'no-asm', 'VC-WIN32'],
                            cwd=root, stdout=subprocess.PIPE, check=True)
    makefile = result.stdout.decode('ascii')
    makefile = re.sub(r'^PERL=.*\n', '', makefile, flags=re.M)
    makefile = re.sub(r'^FIPSLINK=.*\n', '', makefile, flags=re.M)
    makefile = re.sub(r'^CP=.*$', 'CP=copy /Y', makefile, flags=re.M)
    makefile = re.sub(r'^MKDIR=.*$', 'MKDIR=mkdir', makefile, flags=re.M)
    makefile = re.sub(r'\$\(PERL\) \$\(SRC_D\)[/\\]util[/\\]copy-if-different\.pl',
                      '$(CP)', makefile)
    # NMAKE's cmd.exe recipes need Windows separators in the copy operands.
    makefile = '\n'.join(line.replace('/', '\\') if line.startswith('\t$(CP) ')
                         else line for line in makefile.split('\n'))
    assert '$(PERL)' not in makefile, 'unexpected remaining Windows Perl recipe'
    assert '\t$(ASM)' not in makefile, 'unexpected assembler recipe'
    (root / 'ms/nt.mak').write_text(makefile, encoding='ascii')
    for name in ('buildinf', 'opensslconf'):
        shutil.copyfile(root / ('crypto/' + name + '.h'),
                        root / ('crypto/' + name + '_x86.h'))
    print('python34-openssl-input=PASS no-asm no-Windows-perl')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    prepare(args.source.resolve())
