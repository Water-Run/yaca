#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)

if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  export YACA_TEST_MIN_AVAILABLE_MIB=${YACA_TEST_MIN_AVAILABLE_MIB:-4096}
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" bash "$0" "$@"
fi

usage() {
  echo "usage: $0 SOURCE_CACHE YACA_ARCHIVE YACA_REVISION YACA_ARCHIVE_SHA256 OUTPUT" >&2
  exit 64
}

die() {
  echo "linux qualification build: $*" >&2
  exit 1
}

[[ $# -eq 5 ]] || usage

SOURCE_CACHE=$(cd "$1" && pwd -P)
YACA_ARCHIVE=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
YACA_REVISION=$3
YACA_ARCHIVE_SHA256=$4
OUTPUT_PARENT=$(cd "$(dirname "$5")" && pwd -P)
OUTPUT_ROOT="$OUTPUT_PARENT/$(basename "$5")"

[[ -f "$YACA_ARCHIVE" ]] || die "yaca source archive is missing"
[[ "$YACA_REVISION" =~ ^[0-9a-f]{40}$ ]] || die "yaca revision must be a full commit"
[[ "$YACA_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "yaca archive hash must be SHA-256"
[[ ! -e "$OUTPUT_ROOT" ]] || die "output already exists: $OUTPUT_ROOT"
[[ "$(basename "$OUTPUT_ROOT")" != "." && "$(basename "$OUTPUT_ROOT")" != ".." ]] \
  || die "output basename is unsafe"

for command in ar awk chmod cp file gcc getconf grep ldd make mktemp objdump \
  patch perl ranlib readelf sed sha256sum sort tar; do
  command -v "$command" >/dev/null 2>&1 || die "required command is missing: $command"
done

[[ "$(uname -s)" == "Linux" ]] || die "this builder is Linux-only"
[[ "$(uname -m)" == "x86_64" ]] || die "this builder requires x86_64"
grep -Eq '^CentOS Linux release 7\.' /etc/centos-release \
  || die "a real CentOS 7 build host is required"
[[ "$(getconf GNU_LIBC_VERSION)" == "glibc 2.17" ]] \
  || die "the build host must use glibc 2.17"
[[ "$(gcc -dumpversion)" == 4.8.5 ]] \
  || die "the qualification compiler must be GCC 4.8.5"
MEMORY_KIB=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
[[ "$MEMORY_KIB" =~ ^[0-9]+$ && "$MEMORY_KIB" -ge 5242880 ]] \
  || die "onefile generation requires at least 5 GiB of build memory"

umask 077
mkdir -p "$OUTPUT_ROOT/logs" "$OUTPUT_ROOT/work" "$OUTPUT_ROOT/prefix" \
  "$OUTPUT_ROOT/artifacts" "$OUTPUT_ROOT/package"

LOG_ROOT="$OUTPUT_ROOT/logs"
WORK_ROOT="$OUTPUT_ROOT/work"
PREFIX_ROOT="$OUTPUT_ROOT/prefix"
ARTIFACT_ROOT="$OUTPUT_ROOT/artifacts"
PACKAGE_ROOT="$OUTPUT_ROOT/package"

LUA_ARCHIVE="$SOURCE_CACHE/lua-5.5.1.tar.gz"
EXPAT_ARCHIVE="$SOURCE_CACHE/expat-2.8.2.tar.gz"
LUAEXPAT_ARCHIVE="$SOURCE_CACHE/luaexpat-1.5.2.tar.gz"
CURL_ARCHIVE="$SOURCE_CACHE/curl-8.21.0.tar.xz"
MBEDTLS_ARCHIVE="$SOURCE_CACHE/mbedtls-3.6.7.tar.bz2"
CA_BUNDLE="$SOURCE_CACHE/cacert-2026-08-13.pem"
LUAINSTALLER_ARCHIVE="$SOURCE_CACHE/luainstaller-97192d1.tar.gz"

verify_sha256() {
  local path=$1
  local expected=$2
  local actual
  [[ -f "$path" ]] || die "locked input is missing: $path"
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] \
    || die "checksum mismatch for $(basename "$path"): expected=$expected actual=$actual"
}

verify_sha256 "$YACA_ARCHIVE" "$YACA_ARCHIVE_SHA256"
verify_sha256 "$LUA_ARCHIVE" 1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
verify_sha256 "$EXPAT_ARCHIVE" ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
verify_sha256 "$LUAEXPAT_ARCHIVE" 89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f
verify_sha256 "$CURL_ARCHIVE" aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6
verify_sha256 "$MBEDTLS_ARCHIVE" a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
verify_sha256 "$CA_BUNDLE" f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9
verify_sha256 "$LUAINSTALLER_ARCHIVE" 9591cfa9c882c8b110a3aa10dc0a1de22f55ef70a26cf21ee4c087cf879423c2

YACA_SOURCE="$WORK_ROOT/yaca"
LUAINSTALLER_SOURCE="$WORK_ROOT/luainstaller"
mkdir "$YACA_SOURCE" "$LUAINSTALLER_SOURCE"
tar -xzf "$YACA_ARCHIVE" -C "$YACA_SOURCE"
tar -xzf "$LUAINSTALLER_ARCHIVE" -C "$LUAINSTALLER_SOURCE"
tar -xzf "$LUA_ARCHIVE" -C "$WORK_ROOT"
tar -xzf "$EXPAT_ARCHIVE" -C "$WORK_ROOT"
tar -xzf "$LUAEXPAT_ARCHIVE" -C "$WORK_ROOT"
tar -xJf "$CURL_ARCHIVE" -C "$WORK_ROOT"
tar -xjf "$MBEDTLS_ARCHIVE" -C "$WORK_ROOT"

verify_sha256 "$LUAINSTALLER_SOURCE/src/init.lua" \
  55694d5e1c349362206e24a3ee8670977e5ea40fd51f0a457b221c95a84fce2d
verify_sha256 "$LUAINSTALLER_SOURCE/src/manifest.lua" \
  d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065
verify_sha256 "$LUAINSTALLER_SOURCE/src/bundler.lua" \
  502da4a599ee0565d11d6c58455a1834d3333f31f8c247e6ee8260fb1dafcfae
verify_sha256 "$LUAINSTALLER_SOURCE/src/onefile.lua" \
  363e9a78d157821be7d6e222a4494c1f65998f5cc920c6f4cfcc0eee01dae610
verify_sha256 "$YACA_SOURCE/release/patches/luainstaller-1.3.0-resources.patch" \
  974cf25b51ab644c8af60a7f2524a5670b1fea38e35ad733267ac4775c5d9dff
patch --batch --forward --fuzz=0 -d "$LUAINSTALLER_SOURCE" -p1 \
  -i "$YACA_SOURCE/release/patches/luainstaller-1.3.0-resources.patch" \
  >"$LOG_ROOT/luainstaller-patch.log" 2>&1

COMMON_CFLAGS="-O2 -pipe -fPIC -march=x86-64 -mtune=generic -fno-strict-aliasing"
COMMON_LDFLAGS="-Wl,-z,relro,-z,now -Wl,--build-id=none"
export SOURCE_DATE_EPOCH=1787990400
export LC_ALL=C
export TZ=UTC

LUA_SOURCE="$WORK_ROOT/lua-5.5.1"
LUA_PREFIX="$PREFIX_ROOT/lua"
if ! make -C "$LUA_SOURCE/src" -j2 linux \
  MYCFLAGS="$COMMON_CFLAGS" MYLDFLAGS="$COMMON_LDFLAGS" \
  >"$LOG_ROOT/lua-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/lua-build.log" >&2
  die "Lua build failed"
fi
make -C "$LUA_SOURCE" install INSTALL_TOP="$LUA_PREFIX" \
  >>"$LOG_ROOT/lua-build.log" 2>&1
"$LUA_PREFIX/bin/lua" -e 'assert(_VERSION == "Lua 5.5"); print(_VERSION)' \
  >"$LOG_ROOT/lua-runtime.log"

EXPAT_SOURCE="$WORK_ROOT/expat-2.8.2"
EXPAT_BUILD="$WORK_ROOT/expat-build"
EXPAT_PREFIX="$PREFIX_ROOT/expat"
mkdir "$EXPAT_BUILD"
if ! (
  cd "$EXPAT_BUILD"
  env CFLAGS="$COMMON_CFLAGS" LDFLAGS="$COMMON_LDFLAGS" \
    "$EXPAT_SOURCE/configure" \
      --prefix="$EXPAT_PREFIX" --disable-shared --enable-static \
      --without-xmlwf --without-examples --without-tests --without-docbook
  make -j2
  make install
) >"$LOG_ROOT/expat-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/expat-build.log" >&2
  die "Expat build failed"
fi

LUAEXPAT_SOURCE="$WORK_ROOT/luaexpat-1.5.2"
LXP_OUTPUT="$ARTIFACT_ROOT/lxp.so"
if ! gcc -std=c99 -Wall -Wextra $COMMON_CFLAGS \
  -I"$LUA_PREFIX/include" -I"$EXPAT_PREFIX/include" -I"$LUAEXPAT_SOURCE/src" \
  -shared "$LUAEXPAT_SOURCE/src/lxplib.c" "$EXPAT_PREFIX/lib/libexpat.a" \
  $COMMON_LDFLAGS -o "$LXP_OUTPUT" \
  >"$LOG_ROOT/luaexpat-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/luaexpat-build.log" >&2
  die "LuaExpat build failed"
fi

NATIVE_OUTPUT="$ARTIFACT_ROOT/yaca_native.so"
if ! gcc -std=c99 -Wall -Wextra -Werror $COMMON_CFLAGS \
  -I"$LUA_PREFIX/include" -shared "$YACA_SOURCE/native/yaca_native.c" \
  $COMMON_LDFLAGS -o "$NATIVE_OUTPUT" \
  >"$LOG_ROOT/yaca-native-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/yaca-native-build.log" >&2
  die "yaca_native build failed"
fi

env LUA_PATH='' LUA_CPATH="$ARTIFACT_ROOT/?.so" \
  "$LUA_PREFIX/bin/lua" -e 'local n=require("yaca_native"); local p=n.platform_identity(); assert(n.abi_version()=="yaca-native-v0.1.0" and p.os=="linux" and p.arch=="x86_64"); local x=require("lxp"); assert(x._VERSION=="LuaExpat 1.5.2" and x._EXPAT_VERSION=="expat_2.8.2"); print("native-load=PASS")' \
  >"$LOG_ROOT/native-load.log"

NATIVE_COMPONENT_PROBE="$ARTIFACT_ROOT/native-component-probe"
if ! gcc -std=c99 -Wall -Wextra -Werror $COMMON_CFLAGS \
  "$YACA_SOURCE/.tools/qualification/native_component_probe.c" \
  $COMMON_LDFLAGS -o "$NATIVE_COMPONENT_PROBE" \
  >"$LOG_ROOT/native-component-probe-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/native-component-probe-build.log" >&2
  die "native component probe build failed"
fi
env LUA_PATH='' LUA_CPATH='' \
  "$LUA_PREFIX/bin/lua" \
  "$YACA_SOURCE/.tools/qualification/prove_native_component.lua" \
  "$YACA_SOURCE" "$NATIVE_OUTPUT" "$NATIVE_COMPONENT_PROBE" \
  >"$LOG_ROOT/native-component-proof.log"

MBEDTLS_SOURCE="$WORK_ROOT/mbedtls-3.6.7"
MBEDTLS_PREFIX="$PREFIX_ROOT/mbedtls"
if ! make -C "$MBEDTLS_SOURCE" -j2 lib \
  CFLAGS="-std=c99 $COMMON_CFLAGS" ARFLAGS=rcD \
  >"$LOG_ROOT/mbedtls-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/mbedtls-build.log" >&2
  die "Mbed TLS build failed"
fi
mkdir -p "$MBEDTLS_PREFIX/include" "$MBEDTLS_PREFIX/lib"
cp -a "$MBEDTLS_SOURCE/include/mbedtls" "$MBEDTLS_PREFIX/include/"
cp -a "$MBEDTLS_SOURCE/include/psa" "$MBEDTLS_PREFIX/include/"
cp "$MBEDTLS_SOURCE/library/libmbedcrypto.a" \
  "$MBEDTLS_SOURCE/library/libmbedx509.a" \
  "$MBEDTLS_SOURCE/library/libmbedtls.a" "$MBEDTLS_PREFIX/lib/"

CURL_SOURCE="$WORK_ROOT/curl-8.21.0"
CURL_PREFIX="$PREFIX_ROOT/curl"
if ! (
  cd "$CURL_SOURCE"
  env CFLAGS="$COMMON_CFLAGS" CPPFLAGS="-I$MBEDTLS_PREFIX/include" \
    LDFLAGS="-L$MBEDTLS_PREFIX/lib $COMMON_LDFLAGS" PKG_CONFIG=false \
    ./configure \
      --prefix="$CURL_PREFIX" --disable-shared --enable-static \
      --enable-http --disable-ftp --disable-file --disable-ipfs \
      --disable-ldap --disable-ldaps --disable-rtsp --disable-dict \
      --disable-telnet --disable-tftp --disable-pop3 --disable-imap \
      --disable-smb --disable-smtp --disable-gopher --disable-mqtt \
      --disable-manual --disable-docs --disable-libcurl-option \
      --disable-ntlm --disable-tls-srp --disable-unix-sockets \
      --disable-cookies --disable-doh --disable-netrc \
      --disable-alt-svc --disable-hsts --disable-websockets \
      --disable-httpsrr --disable-ech --disable-ssls-export \
      --disable-proxy-http3 --disable-ca-native --disable-ca-search \
      --without-zlib --without-brotli --without-zstd --without-libpsl \
      --without-libidn2 --without-nghttp2 --without-ngtcp2 \
      --without-nghttp3 --without-libssh2 --without-librtmp \
      --without-libgsasl --without-gssapi --without-ca-bundle \
      --without-ca-path --without-ca-fallback --without-ca-embed \
      --without-openssl --without-gnutls --without-wolfssl \
      --without-rustls --without-schannel --without-amissl \
      --with-mbedtls="$MBEDTLS_PREFIX"
  make -j2
) >"$LOG_ROOT/curl-build.log" 2>&1; then
  tail -120 "$LOG_ROOT/curl-build.log" >&2
  die "curl build failed"
fi
cp "$CURL_SOURCE/src/curl" "$ARTIFACT_ROOT/curl"
chmod 0755 "$ARTIFACT_ROOT/curl"
"$ARTIFACT_ROOT/curl" -V >"$LOG_ROOT/curl-version.log"
grep -Eq '^curl 8\.21\.0 .*mbedTLS/3\.6\.7' "$LOG_ROOT/curl-version.log" \
  || die "curl does not report the exact Mbed TLS closure"
[[ "$(sed -n 's/^Protocols: //p' "$LOG_ROOT/curl-version.log")" == "http https" ]] \
  || die "curl protocol surface is not exactly http/https"
if grep -Eq 'Features:.*(alt-svc|HSTS)' "$LOG_ROOT/curl-version.log"; then
  die "curl exposes a disabled persistent network feature"
fi

mkdir -p "$YACA_SOURCE/build/candidates/linux-x86_64"
cp "$NATIVE_OUTPUT" "$YACA_SOURCE/build/candidates/linux-x86_64/yaca_native.so"
cp "$LXP_OUTPUT" "$YACA_SOURCE/build/candidates/linux-x86_64/lxp.so"

if ! (
  cd "$YACA_SOURCE"
  "$LUA_PREFIX/bin/lua" test/run.lua
) >"$LOG_ROOT/full-test.log" 2>&1; then
  tail -120 "$LOG_ROOT/full-test.log" >&2
  die "full target test suite failed"
fi
grep -q '^SUMMARY total=329 passed=329 failed=0$' "$LOG_ROOT/full-test.log" \
  || die "full target test summary changed"

if ! (
  cd "$LUAINSTALLER_SOURCE"
  "$LUA_PREFIX/bin/lua" "$SCRIPT_DIR/package_linux.lua" \
    "$LUAINSTALLER_SOURCE" "$YACA_SOURCE" "$LUA_PREFIX" \
    "$PACKAGE_ROOT/onedir" "$ARTIFACT_ROOT/yaca" \
    "$ARTIFACT_ROOT/curl" "$CA_BUNDLE"
) >"$LOG_ROOT/package.log" 2>&1; then
  tail -120 "$LOG_ROOT/package.log" >&2
  die "luainstaller packaging failed"
fi

EMPTY_HOME="$WORK_ROOT/empty-home"
EMPTY_TMP=$(mktemp -d /tmp/yaca-onefile-smoke-XXXXXX)
mkdir "$EMPTY_HOME"
chmod 0700 "$EMPTY_TMP"
env -i PATH=/usr/bin:/bin HOME="$EMPTY_HOME" TMPDIR="$EMPTY_TMP" \
  "$PACKAGE_ROOT/onedir/onedir" --version >"$LOG_ROOT/onedir-smoke.log"
env -i PATH=/usr/bin:/bin HOME="$EMPTY_HOME" TMPDIR="$EMPTY_TMP" \
  "$ARTIFACT_ROOT/yaca" --version >"$LOG_ROOT/onefile-smoke.log"
grep -q '^yaca 0\.1\.0 (linux-x86_64)$' "$LOG_ROOT/onedir-smoke.log" \
  || die "onedir version smoke failed"
grep -q '^yaca 0\.1\.0 (linux-x86_64)$' "$LOG_ROOT/onefile-smoke.log" \
  || die "onefile version smoke failed"

assert_elf64() {
  local path=$1
  readelf -h "$path" | grep -q 'Class:[[:space:]]*ELF64' \
    || die "not ELF64: $path"
  readelf -h "$path" | grep -q 'Machine:[[:space:]]*Advanced Micro Devices X86-64' \
    || die "not x86-64: $path"
}

assert_system_dependencies() {
  local path=$1
  local dependency
  while IFS= read -r dependency; do
    case "$dependency" in
      libc.so.6|libdl.so.2|libm.so.6|libpthread.so.0|librt.so.1|libgcc_s.so.1) ;;
      *) die "non-system runtime dependency $dependency in $path" ;;
    esac
  done < <(readelf -d "$path" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
}

assert_glibc_baseline() {
  local path=$1
  local maximum
  maximum=$(readelf --version-info "$path" \
    | sed -n 's/.*Name: GLIBC_\([0-9.]*\).*/\1/p' \
    | sort -V | tail -1)
  [[ -z "$maximum" || "$(printf '%s\n%s\n' "$maximum" 2.17 | sort -V | tail -1)" == 2.17 ]] \
    || die "glibc symbol baseline exceeds 2.17 in $path: $maximum"
}

for artifact in "$NATIVE_OUTPUT" "$LXP_OUTPUT" "$ARTIFACT_ROOT/curl" \
  "$PACKAGE_ROOT/onedir/onedir" "$ARTIFACT_ROOT/yaca"; do
  assert_elf64 "$artifact"
  assert_system_dependencies "$artifact"
  assert_glibc_baseline "$artifact"
done

(
  cd "$ARTIFACT_ROOT"
  sha256sum yaca_native.so lxp.so curl yaca
) >"$OUTPUT_ROOT/artifact-sha256.txt"
file "$NATIVE_OUTPUT" "$LXP_OUTPUT" "$ARTIFACT_ROOT/curl" \
  "$ARTIFACT_ROOT/yaca" >"$OUTPUT_ROOT/artifact-file.txt"
ldd "$NATIVE_OUTPUT" "$LXP_OUTPUT" "$ARTIFACT_ROOT/curl" \
  "$ARTIFACT_ROOT/yaca" >"$OUTPUT_ROOT/artifact-ldd.txt"

{
  echo "schema=yaca-linux-build-summary-v1"
  echo "status=PASS"
  echo "target=linux-x86_64"
  echo "minimum=CentOS Linux 7"
  echo "host=$(cat /etc/centos-release)"
  echo "kernel=$(uname -r)"
  echo "arch=$(uname -m)"
  echo "libc=$(getconf GNU_LIBC_VERSION)"
  echo "compiler=$(gcc --version | head -1)"
  echo "build_memory_kib=$MEMORY_KIB"
  echo "yaca_revision=$YACA_REVISION"
  echo "yaca_archive_sha256=$YACA_ARCHIVE_SHA256"
  echo "luainstaller_revision=97192d100077b31b61dc8f94427e14df1c68a9eb"
  echo "luainstaller_patch_sha256=974cf25b51ab644c8af60a7f2524a5670b1fea38e35ad733267ac4775c5d9dff"
  echo "lua=5.5.1"
  echo "expat=2.8.2"
  echo "luaexpat=1.5.2"
  echo "curl=8.21.0"
  echo "mbedtls=3.6.7"
  echo "full_tests=329/329"
  echo "release_authorized=false"
  echo "target_qualification_complete=false"
} >"$OUTPUT_ROOT/build-summary.txt"

cat "$OUTPUT_ROOT/build-summary.txt"
