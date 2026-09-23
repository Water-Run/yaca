#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-09-23
# File: build_win32_std.sh
# Description: Builds pinned portable Windows x86 std tools and stages their source provenance.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
if [[ ${YACA_STD_BUILD_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" env YACA_STD_BUILD_GUARD_HELD=1 bash "$0" "$@"
fi
[[ $# == 4 ]] || { echo "usage: $0 SOURCE_CACHE CORE_BUILD MSI_INVENTORY_TSV NEW_OUTPUT" >&2; exit 64; }
TOOL_CACHE=$(realpath "$1")
CORE_BUILD=$(realpath "$2")
MSI_INVENTORY=$(realpath "$3")
TOOL_OUTPUT=$(realpath -m "$4")
[[ ! -e "$TOOL_OUTPUT" ]] || { echo "tool output already exists" >&2; exit 1; }
for program in cmake i686-w64-mingw32-gcc i686-w64-mingw32-windres python3 patch 7z cabextract tar; do
  command -v "$program" >/dev/null
done
python3 - "$REPO_ROOT" "$TOOL_CACHE" <<'PY'
import hashlib, json, pathlib, sys
repo, cache = map(pathlib.Path, sys.argv[1:])
lock = json.loads((repo / 'release/tool-sources.lock.json').read_text())
for field, root in [('sources', cache), ('patches', repo)]:
    for item in lock[field]:
        actual = hashlib.sha256((root / item['file']).read_bytes()).hexdigest()
        if actual != item['sha256']: raise SystemExit('tool source SHA-256 mismatch: ' + item['file'])
PY
mkdir -p "$TOOL_OUTPUT/build" "$TOOL_OUTPUT/logs"
TOOL_BUILD="$TOOL_OUTPUT/build"
7z x -tCompound -y "-o$TOOL_BUILD/python-msi" "$TOOL_CACHE/python-2.7.18.msi" >"$TOOL_OUTPUT/logs/python-msi.log"
mkdir "$TOOL_BUILD/python-cab"
python3 - "$TOOL_BUILD/python-msi" "$TOOL_BUILD/python-cab" <<'PY'
import pathlib, subprocess, sys
for stream in sorted(pathlib.Path(sys.argv[1]).iterdir()):
    if stream.is_file() and stream.open('rb').read(4) == b'MSCF':
        subprocess.check_call(['cabextract', '-q', '-d', sys.argv[2], str(stream)])
PY
7z x -y "-o$TOOL_BUILD/7zip" "$TOOL_CACHE/7z2603-extra.7z" >"$TOOL_OUTPUT/logs/7zip.log"
tar -xzf "$TOOL_CACHE/putty-0.85.tar.gz" -C "$TOOL_BUILD"
patch --batch --forward --fuzz=0 -d "$TOOL_BUILD/putty-0.85" -p1 \
  -i "$REPO_ROOT/release/patches/putty-0.85-portable.patch" >"$TOOL_OUTPUT/logs/putty-patch.log"
export MAKEFLAGS=-j1 MFLAGS=-j1 SOURCE_DATE_EPOCH=1790035200 LC_ALL=C TZ=UTC
cmake -S "$TOOL_BUILD/putty-0.85" -B "$TOOL_BUILD/putty-build" \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=i686-w64-mingw32-gcc \
  -DCMAKE_RC_COMPILER=i686-w64-mingw32-windres -DCMAKE_BUILD_TYPE=Release \
  -DPUTTY_GSSAPI=OFF \
  '-DCMAKE_C_FLAGS=-Os -DWINVER=0x0501 -D_WIN32_WINNT=0x0501 -DYACA_PORTABLE_TOOLS' \
  '-DCMAKE_EXE_LINKER_FLAGS=-static-libgcc -Wl,--no-insert-timestamp -Wl,--major-subsystem-version,5,--minor-subsystem-version,1' \
  >"$TOOL_OUTPUT/logs/putty-configure.log" 2>&1
cmake --build "$TOOL_BUILD/putty-build" --target plink pscp psftp --parallel 1 >"$TOOL_OUTPUT/logs/putty-build.log" 2>&1
python3 "$SCRIPT_DIR/prepare_win32_std.py" "$TOOL_CACHE" "$TOOL_BUILD" "$CORE_BUILD" \
  "$MSI_INVENTORY" "$TOOL_OUTPUT/staged"
cp "$REPO_ROOT/release/tool-sources.lock.json" "$TOOL_OUTPUT/"
sha256sum "$MSI_INVENTORY" >"$TOOL_OUTPUT/logs/msi-inventory-sha256.txt"
