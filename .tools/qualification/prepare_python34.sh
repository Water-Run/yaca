#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-09-23
# File: prepare_python34.sh
# Description: Prepares exact CPython 3.4.10 source and Windows dependency inputs.

# Prepare the exact CPython 3.4.10 sources and its Win32 dependencies.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
if [[ ${YACA_PY34_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" env YACA_PY34_GUARD_HELD=1 bash "$0" "$@"
fi
[[ $# == 2 ]] || { echo "usage: $0 SOURCE_CACHE NEW_OUTPUT" >&2; exit 64; }
PY34_CACHE=$(realpath "$1")
PY34_OUTPUT=$(realpath -m "$2")
[[ ! -e "$PY34_OUTPUT" ]] || { echo "output already exists" >&2; exit 1; }
for program in tar python3 perl make i686-w64-mingw32-gcc i686-w64-mingw32-ar; do
  command -v "$program" >/dev/null
done
python3 - "$PY34_CACHE" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
inputs = {
 'Python-3.4.10.tar.xz': 'd46a8f6fe91679e199c671b1b0a30aaf172d2acb5bcab25beb35f16c3d195b4e',
 'python-bzip2-1.0.6.tar.gz': '45ffd995f8b4665e262cd79b35352f3b09fa06a71fa621b8ba30e7be59be9cb1',
 'python-openssl-1.0.2k.tar.gz': 'b745566703a6e3bb5ecc8a60a447da8196468ef85a2a23230e76e1579d1b9a19',
 'sqlite-amalgamation-3081100.zip': '09a8a28ce76db0d438852b8698124293fa0c0f0105c9fe79b9e1c2164ba9bcf6',
 'xz-5.0.5.tar.gz': '5dcffe6a3726d23d1711a65288de2e215b4960da5092248ce63c99d50093b93a',
}
for name, expected in inputs.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name
PY
mkdir -p "$PY34_OUTPUT/logs"
tar -xJf "$PY34_CACHE/Python-3.4.10.tar.xz" -C "$PY34_OUTPUT"
PY34_SOURCE="$PY34_OUTPUT/Python-3.4.10"
mkdir -p "$PY34_SOURCE/externals/bzip2-1.0.6" "$PY34_SOURCE/externals/openssl-1.0.2k"
tar -xzf "$PY34_CACHE/python-bzip2-1.0.6.tar.gz" --strip-components=1 -C "$PY34_SOURCE/externals/bzip2-1.0.6"
tar -xzf "$PY34_CACHE/python-openssl-1.0.2k.tar.gz" --strip-components=1 -C "$PY34_SOURCE/externals/openssl-1.0.2k"
tar -xzf "$PY34_CACHE/xz-5.0.5.tar.gz" -C "$PY34_OUTPUT"
python3 - "$PY34_OUTPUT" <<'PY'
import difflib, pathlib, sys
root = pathlib.Path(sys.argv[1])
path = root / 'xz-5.0.5/src/common/tuklib_physmem.c'
original = path.read_text()
old = 'BOOL (WINAPI *gmse)(LPMEMORYSTATUSEX) = GetProcAddress('
new = 'BOOL (WINAPI *gmse)(LPMEMORYSTATUSEX) = (BOOL (WINAPI *)(LPMEMORYSTATUSEX))GetProcAddress('
assert original.count(old) == 1
changed = original.replace(old, new)
path.write_text(changed)
(root / 'xz-5.0.5-build.patch').write_text(''.join(difflib.unified_diff(
    original.splitlines(True), changed.splitlines(True),
    'a/src/common/tuklib_physmem.c', 'b/src/common/tuklib_physmem.c')))
PY
python3 - "$PY34_CACHE" "$PY34_SOURCE" <<'PY'
import pathlib, re, sys, zipfile
cache, root = map(pathlib.Path, sys.argv[1:])
with zipfile.ZipFile(cache / 'sqlite-amalgamation-3081100.zip') as z:
    target = root / 'externals/sqlite-3.8.11.0'
    target.mkdir()
    for name in ('sqlite3.c', 'sqlite3.h', 'sqlite3ext.h'):
        (target / name).write_bytes(z.read('sqlite-amalgamation-3081100/' + name))
# No global/ambient process termination during a private toolbox build.
project = root / 'PCbuild/pythoncore.vcxproj'
original = project.read_text(encoding='utf-8-sig')
changed, count = re.subn(r'    <PreBuildEvent>.*?</PreBuildEvent>\n', '', original, flags=re.S)
assert count == 16
changed, count = re.subn(r'    <ProjectReference Include="kill_python.vcxproj">.*?</ProjectReference>\n', '', changed, flags=re.S)
assert count == 1
project.write_text(changed, encoding='utf-8-sig')
import difflib
(root / 'yaca-build.patch').write_text(''.join(difflib.unified_diff(
    original.splitlines(True), changed.splitlines(True),
    'a/PCbuild/pythoncore.vcxproj', 'b/PCbuild/pythoncore.vcxproj')))
PY
export MAKEFLAGS=-j1 MFLAGS=-j1 SOURCE_DATE_EPOCH=1790035200 LC_ALL=C TZ=UTC
python3 "$SCRIPT_DIR/prepare_python34_ssl.py" "$PY34_SOURCE/externals/openssl-1.0.2k" \
  >"$PY34_OUTPUT/logs/openssl-prepare.log" 2>&1
mkdir "$PY34_OUTPUT/xz-build"
(
  cd "$PY34_OUTPUT/xz-build"
  CC=i686-w64-mingw32-gcc AR=i686-w64-mingw32-ar RANLIB=i686-w64-mingw32-ranlib \
    CFLAGS='-Os -march=i486 -D_WIN32_WINNT=0x0501' \
    "$PY34_OUTPUT/xz-5.0.5/configure" --host=i686-w64-mingw32 \
      --disable-shared --enable-static --disable-nls --disable-scripts --disable-threads
  make -C src/liblzma -j1
) >"$PY34_OUTPUT/logs/xz-build.log" 2>&1
mkdir -p "$PY34_SOURCE/externals/xz-5.0.5/bin_i486"
cp "$PY34_OUTPUT/xz-build/src/liblzma/.libs/liblzma.a" "$PY34_SOURCE/externals/xz-5.0.5/bin_i486/"
cp -r "$PY34_OUTPUT/xz-5.0.5/src/liblzma/api" "$PY34_SOURCE/externals/xz-5.0.5/include"
cp "$SCRIPT_DIR/build_python34_windows.py" "$PY34_OUTPUT/"
python3 - "$PY34_OUTPUT" <<'PY'
import pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(root / 'python34-build-input.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted((root / 'Python-3.4.10').rglob('*')):
        if path.is_file(): z.write(path, path.relative_to(root))
    z.write(root / 'build_python34_windows.py', 'build_python34_windows.py')
PY
echo "python34-build-input=PASS version=3.4.10"
