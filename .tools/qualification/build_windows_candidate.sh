#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-09-23
# File: build_windows_candidate.sh
# Description: Builds Windows candidate payloads and checks their legacy import closure.

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

# Stop the selected Windows candidate build with a diagnostic.
#@param ... string Diagnostic words joined by the shell.
#@return void Exits with failure status 1.
die() { echo "Windows candidate: $*" >&2; exit 1; }
[[ $# == 2 || $# == 3 ]] || die "usage: $0 SOURCE_CACHE NEW_OUTPUT_DIRECTORY [win32-x86|win64-x86_64]"
TARGET=${3:-win32-x86}
case "$TARGET" in
  win32-x86) CROSS=i686-w64-mingw32; WINVER=0x0501; SUBSYSTEM_MAJOR=5; HTTPS_BUILD=build_win32_xp_https_candidate.sh ;;
  win64-x86_64) CROSS=x86_64-w64-mingw32; WINVER=0x0601; SUBSYSTEM_MAJOR=6; HTTPS_BUILD=build_win64_https_candidate.sh ;;
  *) die "unsupported Windows target: $TARGET" ;;
esac
SOURCE_CACHE=$(cd "$1" && pwd -P)
OUTPUT_ROOT=$(realpath -m "$2")
[[ ! -e "$OUTPUT_ROOT" ]] || die "output already exists"
for command in "$CROSS-gcc" "$CROSS-objdump" \
  "$CROSS-ar" "$CROSS-ranlib" make patch python3 sha256sum tar git awk realpath; do
  command -v "$command" >/dev/null || die "missing command: $command"
done
umask 077
mkdir -p "$OUTPUT_ROOT/work" "$OUTPUT_ROOT/logs" "$OUTPUT_ROOT/onedir/.luai/native" \
  "$OUTPUT_ROOT/onedir/.luai/components" "$OUTPUT_ROOT/generated" "$OUTPUT_ROOT/package"
WORK_ROOT="$OUTPUT_ROOT/work"
LOG_ROOT="$OUTPUT_ROOT/logs"
STAGE_ROOT="$OUTPUT_ROOT/onedir"
YACA_SOURCE="$WORK_ROOT/yaca"
BUILDER_ROOT="$WORK_ROOT/luainstaller"
LUA_SOURCE="$WORK_ROOT/lua-5.5.1/src"

# Check a locked Windows source file against its pinned SHA-256 digest.
#@param 1 string Source file path.
#@param 2 string Expected lowercase SHA-256 digest.
#@return int Zero on a match; failure exits through die.
verify() {
  [[ -f "$1" ]] || die "missing locked input: $1"
  [[ $(sha256sum "$1" | awk '{print $1}') == "$2" ]] || die "SHA-256 mismatch: $1"
}
verify "$SOURCE_CACHE/lua-5.5.1.tar.gz" \
  1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
verify "$SOURCE_CACHE/expat-2.8.2.tar.gz" \
  ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
verify "$SOURCE_CACHE/luaexpat-1.5.2.tar.gz" \
  89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f
verify "$SOURCE_CACHE/luainstaller-97192d1.tar.gz" \
  9591cfa9c882c8b110a3aa10dc0a1de22f55ef70a26cf21ee4c087cf879423c2
verify "$SOURCE_CACHE/cacert-2026-08-13.pem" \
  f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9

# Snapshot only tracked project inputs (including current edits), never user
# configuration, historical bin/, source-cache contents or ambient credentials.
mkdir "$YACA_SOURCE" "$BUILDER_ROOT"
git -C "$REPO_ROOT" ls-files -z | python3 -c '
import os, subprocess, sys
root = sys.argv[1]
deleted = set(subprocess.check_output(["git", "-C", root, "ls-files", "--deleted", "-z"]).split(b"\0"))
sys.stdout.buffer.write(b"\0".join(name for name in sys.stdin.buffer.read().split(b"\0")
    if name and name not in deleted) + b"\0")
' "$REPO_ROOT" | tar -C "$REPO_ROOT" --null -T - -cf - \
  | tar -C "$YACA_SOURCE" -xf -
cp "$SCRIPT_DIR/windows_sources.lua" "$YACA_SOURCE/.tools/qualification/"
cp "$SCRIPT_DIR/build_windows_candidate.sh" "$SCRIPT_DIR/windows_package.py" \
  "$SCRIPT_DIR/windows_native_smoke.lua" "$SCRIPT_DIR/windows_network_smoke.lua" \
  "$SCRIPT_DIR/windows_mock_provider.ps1" \
  "$YACA_SOURCE/.tools/qualification/"
cp "$REPO_ROOT/release/WINDOWS-QUICKSTART.md" "$YACA_SOURCE/release/"
cp "$REPO_ROOT/release/launcher.lua" "$YACA_SOURCE/release/"
cp "$REPO_ROOT/native/yaca_entry.c" "$YACA_SOURCE/native/"
cp "$REPO_ROOT/native/yaca_pty.h" "$YACA_SOURCE/native/"
cp "$REPO_ROOT/native/yaca_onefile_windows.h" "$REPO_ROOT/native/yaca_onefile_entry.c" "$YACA_SOURCE/native/"
cp "$REPO_ROOT/native/yaca_lua_windows.h" "$YACA_SOURCE/native/"
cp "$REPO_ROOT/native/yaca_supervisor.h" "$YACA_SOURCE/native/"
for input in release/tool-bundles.json release/TOOL-BUNDLES.md \
  release/tool-sources.lock.json release/patches/putty-0.85-portable.patch \
  release/patches/jq-1.8.2-xp.patch \
  .tools/package_editions.py .tools/qualification/interpreter_smoke.py \
  .tools/qualification/build_win64_https_candidate.sh \
  .tools/qualification/build_win32_std.sh .tools/qualification/prepare_win32_std.py \
  test/release/editions_test.py test/integration/first_run_test.lua \
  test/integration/review_queue_ask_test.lua \
  .tools/qualification/msi_inventory.c .tools/qualification/windows_pty_smoke.c \
  .tools/qualification/windows_std_smoke.py \
  .tools/qualification/windows_portable_acceptance.py \
  .tools/qualification/windows_console_agent_smoke.py \
  .tools/qualification/windows_inherited_smoke.py \
  .tools/qualification/windows_filesystem_identity_smoke.c \
  .tools/qualification/lua_tool_smoke.lua \
  .tools/qualification/process_tree_smoke.lua .tools/qualification/agent_terminal_smoke.py \
  .tools/qualification/linux_supervisor_smoke.lua .tools/qualification/process_stdin_smoke.lua \
  .tools/qualification/linux_supervisor_smoke.py \
  .tools/qualification/windows_console_smoke.c \
  .tools/qualification/extract_sdk71.py .tools/qualification/prepare_python34.sh \
  .tools/qualification/build_python34_windows.py \
  .tools/qualification/stage_python34_windows.py \
  .tools/qualification/prepare_python34_ssl.py .tools/qualification/windows_unicode_smoke.c \
  .develope-docs/CODE-REVIEW-2026-09-22.md \
  .develope-docs/BASELINE-REVIEW-2026-09-22.md \
  .develope-docs/MAJOR-REDESIGN-PLAN-2026-09-22.md \
  .develope-docs/PRODUCT-ROADMAP-2026-09-22.md \
  .develope-docs/PORTABLE-IMPLEMENTATION-2026-09-22.md \
  .develope-docs/references/agent-loop-source-review-2026-09-22.md; do
  cp "$REPO_ROOT/$input" "$YACA_SOURCE/$input"
done
cp "$REPO_ROOT/.develope-docs/WINDOWS-PREVIEW-2026-09-14.md" "$YACA_SOURCE/.develope-docs/"
git -C "$REPO_ROOT" rev-parse HEAD >"$LOG_ROOT/base-revision.txt"
git -C "$REPO_ROOT" diff --binary HEAD >"$LOG_ROOT/source-changes.patch"
tar -C "$YACA_SOURCE" -czf "$OUTPUT_ROOT/yaca-source.tar.gz" .
tar -C "$BUILDER_ROOT" -xzf "$SOURCE_CACHE/luainstaller-97192d1.tar.gz"
for archive in lua-5.5.1 expat-2.8.2 luaexpat-1.5.2; do
  tar -C "$WORK_ROOT" -xzf "$SOURCE_CACHE/$archive.tar.gz"
done

# Windows must put DLLs first: yaca intentionally loads only the first trusted
# native template, while upstream's generic bootstrap starts with Unix .so.
python3 - "$BUILDER_ROOT/src/cgen.lua" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
source = path.read_text()
old = '''    resolved .. "/?.so",
    resolved .. "/?/init.so",
    resolved .. "/?.dylib",
    resolved .. "/?/init.dylib",
    resolved .. "/?.dll",
    resolved .. "/?/init.dll",'''
new = '''    resolved .. "/?.dll",
    resolved .. "/?/init.dll",'''
assert source.count(old) == 1
path.write_text(source.replace(old, new))
PY

# On XP through Windows 7, curl/shell children cannot nest inside the outer
# launcher's job. Native process_start explicitly breaks away and places each
# suspended child into its own kill-on-close job before resuming it.
python3 - "$BUILDER_ROOT/src/onefile.lua" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
source = path.read_text()
old = "job_info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;"
new = ("job_info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE"
       " | JOB_OBJECT_LIMIT_BREAKAWAY_OK;")
assert source.count(old) == 1
path.write_text(source.replace(old, new))
PY

export SOURCE_DATE_EPOCH=1789344000 LC_ALL=C TZ=UTC MAKEFLAGS=-j1 MFLAGS=-j1
CC="$CROSS-gcc"
CFLAGS="-Os -DWINVER=$WINVER -D_WIN32_WINNT=$WINVER -ffunction-sections -fdata-sections"
LDFLAGS="-static-libgcc -Wl,--gc-sections -Wl,--no-insert-timestamp \
-Wl,--major-subsystem-version,$SUBSYSTEM_MAJOR,--minor-subsystem-version,1"
cp "$REPO_ROOT/native/yaca_lua_windows.h" "$LUA_SOURCE/"
# Lua's upstream Windows path buffer counts ANSI bytes. Our UTF-8 adapter
# needs up to three bytes per UTF-16 unit, including legal old-system paths
# whose UTF-8 encoding exceeds MAX_PATH. This changes no interpreter semantics.
python3 - "$LUA_SOURCE/loadlib.c" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
source = path.read_text()
old = 'char buff[MAX_PATH + 1];'
assert source.count(old) == 1
path.write_text(source.replace(old, 'char buff[32768 * 3 + 1];'))
PY
# Keep Lua's public interpreter/VM source unchanged. The platform adapter maps
# UTF-8 filesystem paths to the XP wide CRT and loader APIs.
make -C "$LUA_SOURCE" -j1 lua.exe CC="$CC -std=gnu99" \
  LUA_A=lua55.dll LUA_T=lua.exe SYSCFLAGS=-DLUA_BUILD_AS_DLL \
  AR="$CC -shared $LDFLAGS -Wl,--out-implib,$LUA_SOURCE/liblua55.a -o" \
  RANLIB=true MYCFLAGS="$CFLAGS -include yaca_lua_windows.h" MYLDFLAGS="$LDFLAGS" \
  >"$LOG_ROOT/lua-build.log" 2>&1
cp "$LUA_SOURCE/lua55.dll" "$STAGE_ROOT/"

mkdir "$WORK_ROOT/expat-build"
(
  cd "$WORK_ROOT/expat-build"
  env CC="$CC" AR="$CROSS-ar" RANLIB="$CROSS-ranlib" \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    "$WORK_ROOT/expat-2.8.2/configure" --host="$CROSS" \
      --disable-shared --enable-static --without-xmlwf --without-examples \
      --without-tests --without-docbook --prefix="$WORK_ROOT/expat-prefix"
  make -j1
  make -j1 install
) >"$LOG_ROOT/expat-build.log" 2>&1
$CC -std=c99 $CFLAGS -shared -DLUA_BUILD_AS_DLL -DXML_STATIC \
  -I"$LUA_SOURCE" -I"$WORK_ROOT/expat-prefix/include" \
  -I"$WORK_ROOT/luaexpat-1.5.2/src" "$WORK_ROOT/luaexpat-1.5.2/src/lxplib.c" \
  "$WORK_ROOT/expat-prefix/lib/libexpat.a" "$LUA_SOURCE/liblua55.a" $LDFLAGS \
  -o "$STAGE_ROOT/.luai/native/lxp.dll" >"$LOG_ROOT/lxp-build.log" 2>&1
$CC -std=c99 -Wall -Wextra -Werror $CFLAGS -shared -DLUA_BUILD_AS_DLL \
  -I"$LUA_SOURCE" "$YACA_SOURCE/native/yaca_native.c" "$LUA_SOURCE/liblua55.a" \
  $LDFLAGS -ladvapi32 -lshell32 -o "$STAGE_ROOT/.luai/native/yaca_native.dll" \
  >"$LOG_ROOT/native-build.log" 2>&1
$CC -std=c99 -Wall -Wextra -Werror $CFLAGS -DLUA_BUILD_AS_DLL \
  -I"$LUA_SOURCE" "$YACA_SOURCE/.tools/qualification/windows_metadata_smoke.c" \
  "$LUA_SOURCE/liblua55.a" $LDFLAGS -ladvapi32 -lshell32 \
  -o "$OUTPUT_ROOT/windows_metadata_smoke.exe" \
  >"$LOG_ROOT/metadata-smoke-build.log" 2>&1
$CC -std=c99 -Wall -Wextra -Werror $CFLAGS -DLUA_BUILD_AS_DLL \
  -I"$LUA_SOURCE" "$YACA_SOURCE/.tools/qualification/windows_console_reader_smoke.c" \
  "$LUA_SOURCE/liblua55.a" $LDFLAGS -ladvapi32 -lshell32 \
  -o "$OUTPUT_ROOT/windows_console_reader_smoke.exe" \
  >"$LOG_ROOT/console-reader-smoke-build.log" 2>&1
$CC -std=c99 -Wall -Wextra -Werror $CFLAGS \
  "$YACA_SOURCE/.tools/qualification/windows_pty_smoke.c" $LDFLAGS \
  -o "$OUTPUT_ROOT/windows_pty_smoke.exe" >"$LOG_ROOT/pty-smoke-build.log" 2>&1

bash "$REPO_ROOT/.tools/qualification/$HTTPS_BUILD" \
  "$SOURCE_CACHE" "$OUTPUT_ROOT/https" >"$LOG_ROOT/https-build.log" 2>&1
cp "$OUTPUT_ROOT/https/artifacts/curl.exe" "$STAGE_ROOT/.luai/components/"
cp "$SOURCE_CACHE/cacert-2026-08-13.pem" "$STAGE_ROOT/.luai/components/cacert.pem"

"$REPO_ROOT/bin/lua55" "$SCRIPT_DIR/windows_sources.lua" "$BUILDER_ROOT" \
  "$YACA_SOURCE" launcher "$OUTPUT_ROOT/generated/launcher.c" \
  "$LUA_SOURCE" \
  >"$LOG_ROOT/launcher-generation.log" 2>&1
$CC $CFLAGS -DLUA_BUILD_AS_DLL -I"$LUA_SOURCE" "$OUTPUT_ROOT/generated/launcher.c" \
  "$LUA_SOURCE/liblua55.a" $LDFLAGS -lshell32 -o "$STAGE_ROOT/inner.exe" \
  >"$LOG_ROOT/launcher-build.log" 2>&1
"$REPO_ROOT/bin/lua55" "$SCRIPT_DIR/windows_sources.lua" "$BUILDER_ROOT" \
  "$YACA_SOURCE" extractor "$OUTPUT_ROOT/generated" "$STAGE_ROOT" \
  >"$LOG_ROOT/extractor-generation.log" 2>&1
$CC $CFLAGS -municode "$OUTPUT_ROOT/generated/extractor.c" $LDFLAGS -ladvapi32 \
  -o "$OUTPUT_ROOT/package/yaca.exe" >"$LOG_ROOT/extractor-build.log" 2>&1

python3 "$SCRIPT_DIR/windows_package.py" "$REPO_ROOT" "$OUTPUT_ROOT" "$SOURCE_CACHE" "$TARGET"
echo "Windows candidate built: $OUTPUT_ROOT"
echo "Real-target qualification remains pending for $TARGET."
