#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-10-02
# File: build_win32_full_tools.sh
# Description: Cross-builds the win32 full in-lock tools for XP and unpacks the pinned portable externals.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)

BUILD_MINIMUM_AVAILABLE_MIB=5120
YACA_TEST_MIN_AVAILABLE_MIB=${YACA_TEST_MIN_AVAILABLE_MIB:-$BUILD_MINIMUM_AVAILABLE_MIB}
[[ "$YACA_TEST_MIN_AVAILABLE_MIB" =~ ^[1-9][0-9]{0,6}$ ]] || exit 75
(( YACA_TEST_MIN_AVAILABLE_MIB >= BUILD_MINIMUM_AVAILABLE_MIB )) \
  || YACA_TEST_MIN_AVAILABLE_MIB=$BUILD_MINIMUM_AVAILABLE_MIB
export YACA_TEST_MIN_AVAILABLE_MIB
if [[ ${YACA_WINDOWS_BUILD_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" \
    env YACA_WINDOWS_BUILD_RESOURCE_GUARD_HELD=1 bash "$0" "$@"
fi

# Stop the win32 full tool build with its failing precondition.
#@param ... string Diagnostic words joined by the shell.
#@return void Exits with failure status 1.
die() { echo "win32 full tools: $*" >&2; exit 1; }

# Check a locked win64 full input against its pinned SHA-256 digest.
#@param 1 string Input file path.
#@param 2 string Expected lowercase SHA-256 digest.
#@return void No value; a mismatch exits through die.
verify() {
  [[ -f "$1" ]] || die "missing locked input: $1"
  [[ $(sha256sum "$1" | awk '{print $1}') == "$2" ]] || die "SHA-256 mismatch: $1"
}

# Run one Windows payload under wine with an isolated prefix and capture output.
#@param ... string Command words starting with the payload path.
#@return void No value; wine output goes to stdout for the caller's log.
run_wine() {
  env WINEPREFIX="$WORK_ROOT/wineprefix" WINEDEBUG=-all wine "$@"
}

[[ $# == 4 ]] || die "usage: $0 SOURCES PAYLOADS BUSYBOX64_EXE NEW_OUTPUT"
SOURCES=$(cd "$1" && pwd -P)
PAYLOADS=$(cd "$2" && pwd -P)
BUSYBOX64_EXE=$(realpath "$3")
OUTPUT_ROOT=$(realpath -m "$4")
[[ ! -e "$OUTPUT_ROOT" ]] || die "output already exists"
for command in i686-w64-mingw32-gcc i686-w64-mingw32-objdump \
  i686-w64-mingw32-ar i686-w64-mingw32-ranlib make patch python3 \
  sha256sum tar unzip 7z wine awk realpath; do
  command -v "$command" >/dev/null || die "missing command: $command"
done

# Locked in-tree sources from release/full-tool-sources.lock.json.
verify "$SOURCES/jq-1.8.2.tar.gz" \
  71b8d6e8f5fe81f6c6d0d110e3892251f6ce76ed095abd315e26e6e1193af3af
verify "$SOURCES/onig-6.9.10.tar.gz" \
  2a5cfc5ae259e4e97f86b68dfffc152cdaffe94e2060b770cb827238d769fc05
verify "$SOURCES/sqlite-autoconf-3530400.tar.gz" \
  0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c
verify "$SOURCES/sqlite-src-3530400.zip" \
  d18fa15aec74d8c17e1463f861095adc01b5ad190256acb4f91d22f0368d232b
verify "$SOURCES/busybox-w32-FRP-6075-g169694ebd.tar.gz" \
  aa953010f16989cec8e165c5ffddaa9f6633f65670e20d5d7678c987d776f1d7
# External portable payloads pinned by the original build machine's
# payloads.lock.json (out/full-payloads-20260929); D-079 tier-1/2 records agree.
verify "$PAYLOADS/w64devkit-x86-2.9.0.7z.exe" \
  d05b743dfade0bd063a5f0587f628b0668ddb666fe194d71f42c88377d9595e9
verify "$PAYLOADS/PortableGit-2.10.0-32-bit.7z.exe" \
  89940cca2a8e1b18b5ed6e3d46c97ea4fcfe1628cda3ae452cd2a8984a3c25c8
verify "$BUSYBOX64_EXE" \
  ca28b094afeeb8f3f01043034f4f63d1b4070e5e37909ab424c8561881e6301e

umask 077
mkdir -p "$OUTPUT_ROOT/work" "$OUTPUT_ROOT/logs" "$OUTPUT_ROOT/out/jq" \
  "$OUTPUT_ROOT/out/sqlite" "$OUTPUT_ROOT/out/busybox" "$OUTPUT_ROOT/unpack"
WORK_ROOT="$OUTPUT_ROOT/work"
LOG_ROOT="$OUTPUT_ROOT/logs"
export SOURCE_DATE_EPOCH=1789344000 LC_ALL=C TZ=UTC MAKEFLAGS=-j1 MFLAGS=-j1
CROSS=i686-w64-mingw32
CFLAGS="-Os -DWINVER=0x0501 -D_WIN32_WINNT=0x0501 -ffunction-sections -fdata-sections"
LDFLAGS="-static -static-libgcc -Wl,--gc-sections -Wl,--major-subsystem-version,5,--minor-subsystem-version,1"

# jq 1.8.2 with its vendored oniguruma and the locked XP patch (XP msvcrt
# has no _mkgmtime64), fully static so no libwinpthread or
# libgcc DLL travels with the tool (the win32 round initially linked
# libwinpthread dynamically and had to be relinked; here -static is set up front).
mkdir "$WORK_ROOT/jq-build"
tar -C "$WORK_ROOT/jq-build" -xzf "$SOURCES/jq-1.8.2.tar.gz"
(
  cd "$WORK_ROOT/jq-build/jq-1.8.2"
  patch -p1 --batch <"$REPO_ROOT/release/patches/jq-1.8.2-xp.patch"
  env CC="$CROSS-gcc" AR="$CROSS-ar" RANLIB="$CROSS-ranlib" \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    ./configure --host="$CROSS" --disable-shared --enable-static \
      --disable-docs >/dev/null
  make -j1
  # libtool drops the static preference from the program link; link jq.exe
  # directly with the compiler driver against the built static archives,
  # exactly like the recorded win32 fix. jq 1.8.2 uses the unicode wmain
  # entry, so the driver needs -municode for the wide startup wiring.
  "$CROSS-gcc" $CFLAGS -municode -o jq.exe src/main.o .libs/libjq.a \
    vendor/oniguruma/src/.libs/libonig.a -lshlwapi -lm $LDFLAGS
) >"$LOG_ROOT/jq-build.log" 2>&1 || { tail -30 "$LOG_ROOT/jq-build.log"; die "jq build failed"; }
cp "$WORK_ROOT/jq-build/jq-1.8.2/jq.exe" "$OUTPUT_ROOT/out/jq/jq.exe"
cp "$WORK_ROOT/jq-build/jq-1.8.2/COPYING" "$OUTPUT_ROOT/out/jq/COPYING"
"$CROSS-objdump" -p "$OUTPUT_ROOT/out/jq/jq.exe" | awk '/DLL Name/{print $NF}' \
  >"$LOG_ROOT/jq-imports.txt"
if grep -qi 'winpthread\|libgcc\|libstdc' "$LOG_ROOT/jq-imports.txt"; then
  die "jq.exe links a mingw runtime DLL"
fi

# sqlite3 CLI from the locked autoconf amalgamation package.
mkdir "$WORK_ROOT/sqlite-autoconf"
tar -C "$WORK_ROOT/sqlite-autoconf" -xzf "$SOURCES/sqlite-autoconf-3530400.tar.gz"
(
  cd "$WORK_ROOT/sqlite-autoconf/sqlite-autoconf-3530400"
  env CC="$CROSS-gcc" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    ./configure --host="$CROSS" --disable-shared --enable-static \
      >/dev/null
  make -j1
) >"$LOG_ROOT/sqlite-build.log" 2>&1 || { tail -30 "$LOG_ROOT/sqlite-build.log"; die "sqlite3 build failed"; }
cp "$WORK_ROOT/sqlite-autoconf/sqlite-autoconf-3530400/sqlite3.exe" \
  "$OUTPUT_ROOT/out/sqlite/sqlite3.exe"

# sqldiff from the locked source package plus the autoconf amalgamation, per
# the recorded win32 recipe (tool/sqldiff.c + ext/misc/sqlite3_stdio.c).
mkdir "$WORK_ROOT/sqlite-src"
unzip -q "$SOURCES/sqlite-src-3530400.zip" -d "$WORK_ROOT/sqlite-src"
(
  cd "$WORK_ROOT/sqlite-src/sqlite-src-3530400"
  "$CROSS-gcc" -O2 -I"$WORK_ROOT/sqlite-autoconf/sqlite-autoconf-3530400" \
    -Iext/misc \
    -o "$OUTPUT_ROOT/out/sqlite/sqldiff.exe" \
    tool/sqldiff.c ext/misc/sqlite3_stdio.c \
    "$WORK_ROOT/sqlite-autoconf/sqlite-autoconf-3530400/sqlite3.c" \
    $LDFLAGS
) >"$LOG_ROOT/sqldiff-build.log" 2>&1 || { tail -30 "$LOG_ROOT/sqldiff-build.log"; die "sqldiff build failed"; }
cp "$WORK_ROOT/sqlite-src/sqlite-src-3530400/LICENSE.md" \
  "$OUTPUT_ROOT/out/sqlite/LICENSE.md"
"$CROSS-objdump" -p "$OUTPUT_ROOT/out/sqlite/sqlite3.exe" | awk '/DLL Name/{print $NF}' \
  >"$LOG_ROOT/sqlite-imports.txt"
if grep -qi 'winpthread\|libgcc\|libstdc' "$LOG_ROOT/sqlite-imports.txt"; then
  die "sqlite3.exe links a mingw runtime DLL"
fi

# busybox-w32 x64: the digest-verified artifact already recorded by the
# original build machine's payloads.lock.json (busybox-w32-win64.exe),
# rebuilt from the same locked FRP-6075 source; only the notices are staged.
tar -C "$WORK_ROOT" -xzf "$SOURCES/busybox-w32-FRP-6075-g169694ebd.tar.gz" \
  busybox-w32-FRP-6075-g169694ebd/LICENSE
cp "$BUSYBOX64_EXE" "$OUTPUT_ROOT/out/busybox/busybox.exe"
cp "$WORK_ROOT/busybox-w32-FRP-6075-g169694ebd/LICENSE" \
  "$OUTPUT_ROOT/out/busybox/LICENSE"

# w64devkit x64 portable devkit, unpacked from the digest-verified SFX.
7z x -y -o"$WORK_ROOT/w64devkit-sfx" "$PAYLOADS/w64devkit-x86-2.9.0.7z.exe" \
  >"$LOG_ROOT/w64devkit-unpack.log" 2>&1 || die "w64devkit unpack failed"
[[ -d "$WORK_ROOT/w64devkit-sfx/w64devkit" ]] || die "w64devkit layout unexpected"
mv "$WORK_ROOT/w64devkit-sfx/w64devkit" "$OUTPUT_ROOT/unpack/w64devkit"
cp "$LOG_ROOT/w64devkit-unpack.log" "$OUTPUT_ROOT/unpack/w64devkit-unpack.log"

# PortableGit 2.46.2-64, unpacked at the staging root like the win32 recipe.
7z x -y -o"$OUTPUT_ROOT/unpack" "$PAYLOADS/PortableGit-2.10.0-32-bit.7z.exe" \
  >"$LOG_ROOT/portablegit-unpack.log" 2>&1 || die "PortableGit unpack failed"
cp "$LOG_ROOT/portablegit-unpack.log" "$OUTPUT_ROOT/unpack/portablegit-unpack.log"
[[ -f "$OUTPUT_ROOT/unpack/cmd/git.exe" && -f "$OUTPUT_ROOT/unpack/LICENSE.txt" ]] \
  || die "PortableGit layout unexpected"

# Smoke every payload under wine with an isolated prefix; versions go to the
# record so the review can compare them against the locked versions.
{
  echo "== win32 full tools smoke =="
  echo "jq: $(run_wine "$OUTPUT_ROOT/out/jq/jq.exe" --version 2>/dev/null)"
  echo "sqlite3: $(run_wine "$OUTPUT_ROOT/out/sqlite/sqlite3.exe" --version 2>/dev/null)"
  echo "sqldiff: $(run_wine "$OUTPUT_ROOT/out/sqlite/sqldiff.exe" --version 2>/dev/null)"
  echo "busybox: $(run_wine "$OUTPUT_ROOT/out/busybox/busybox.exe" echo BB_W32_FULL_OK 2>/dev/null)"
  echo "git: $(run_wine "$OUTPUT_ROOT/unpack/cmd/git.exe" --version 2>/dev/null)"
  echo "gcc: $(run_wine "$OUTPUT_ROOT/unpack/w64devkit/bin/gcc.exe" --version 2>/dev/null | head -1)"
} >"$LOG_ROOT/smoke.log" 2>&1
cat "$LOG_ROOT/smoke.log"

echo "win32-full-tools=PASS"
