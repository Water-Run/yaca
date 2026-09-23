#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-09-23
# File: build_win64_https_candidate.sh
# Description: Builds the pinned curl TLS carrier for Windows x64 compatibility checks.

# Build the locked, unmodified HTTPS dependencies for Windows 7 x64.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" bash "$0" "$@"
fi
[[ $# == 2 ]] || { echo "usage: $0 SOURCE_CACHE NEW_OUTPUT" >&2; exit 64; }
CACHE=$(realpath "$1")
OUTPUT=$(realpath -m "$2")
[[ ! -e "$OUTPUT" ]] || { echo "output already exists" >&2; exit 1; }
for program in x86_64-w64-mingw32-gcc x86_64-w64-mingw32-ar \
  x86_64-w64-mingw32-ranlib x86_64-w64-mingw32-objdump make tar python3; do
  command -v "$program" >/dev/null
done
python3 - "$CACHE" <<'PY'
import hashlib, pathlib, sys
cache = pathlib.Path(sys.argv[1])
for name, expected in {
    'curl-8.21.0.tar.xz': 'aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6',
    'mbedtls-3.6.7.tar.bz2': 'a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6',
}.items():
    assert hashlib.sha256((cache / name).read_bytes()).hexdigest() == expected, name
PY
umask 077
mkdir -p "$OUTPUT/work" "$OUTPUT/logs" "$OUTPUT/artifacts" \
  "$OUTPUT/prefix/mbedtls/include" "$OUTPUT/prefix/mbedtls/lib"
tar -xJf "$CACHE/curl-8.21.0.tar.xz" -C "$OUTPUT/work"
tar -xjf "$CACHE/mbedtls-3.6.7.tar.bz2" -C "$OUTPUT/work"
MBEDTLS="$OUTPUT/work/mbedtls-3.6.7"
PREFIX="$OUTPUT/prefix/mbedtls"
export MAKEFLAGS=-j1 MFLAGS=-j1 LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1790035200
CFLAGS='-Os -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -ffunction-sections -fdata-sections'
LDFLAGS='-static -Wl,--gc-sections -Wl,--no-insert-timestamp -Wl,--major-subsystem-version,6,--minor-subsystem-version,1'
make -C "$MBEDTLS" -j1 lib CC=x86_64-w64-mingw32-gcc AR=x86_64-w64-mingw32-ar \
  ARFLAGS=rcD CFLAGS="-std=c99 $CFLAGS" >"$OUTPUT/logs/mbedtls-build.log" 2>&1
cp -a "$MBEDTLS/include/mbedtls" "$MBEDTLS/include/psa" "$PREFIX/include/"
cp "$MBEDTLS/library/libmbedcrypto.a" "$MBEDTLS/library/libmbedx509.a" \
  "$MBEDTLS/library/libmbedtls.a" "$PREFIX/lib/"
(
  cd "$OUTPUT/work/curl-8.21.0"
  env CC=x86_64-w64-mingw32-gcc AR=x86_64-w64-mingw32-ar \
    RANLIB=x86_64-w64-mingw32-ranlib CFLAGS="$CFLAGS" \
    CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib $LDFLAGS" LIBS=-lbcrypt PKG_CONFIG=false \
    ./configure --host=x86_64-w64-mingw32 --disable-shared --enable-static \
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
      --disable-sspi --disable-negotiate-auth --disable-kerberos-auth \
      --without-zlib --without-brotli --without-zstd --without-libpsl \
      --without-libidn2 --without-nghttp2 --without-ngtcp2 \
      --without-nghttp3 --without-libssh2 --without-libgsasl \
      --without-gssapi --without-ca-bundle --without-ca-path \
      --without-ca-fallback --without-ca-embed --without-openssl \
      --without-gnutls --without-wolfssl --without-rustls \
      --without-schannel --without-amissl --with-mbedtls="$PREFIX"
  make -j1
) >"$OUTPUT/logs/curl-build.log" 2>&1
cp "$OUTPUT/work/curl-8.21.0/src/curl.exe" "$OUTPUT/artifacts/curl.exe"
x86_64-w64-mingw32-objdump -p "$OUTPUT/artifacts/curl.exe" >"$OUTPUT/curl-objdump.txt"
python3 - "$OUTPUT" <<'PY'
import hashlib, json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
report = (root / 'curl-objdump.txt').read_text()
assert 'file format pei-x86-64' in report
assert re.search(r'^MajorSubsystemVersion\s+6$', report, re.M)
assert re.search(r'^MinorSubsystemVersion\s+1$', report, re.M)
imports = set(re.findall(r'dll name: (\S+)', report.lower()))
assert imports <= {'kernel32.dll', 'msvcrt.dll', 'advapi32.dll', 'ws2_32.dll', 'bcrypt.dll', 'iphlpapi.dll'}, imports
assert 'bcrypt.dll' in imports
banned = r'api-ms-win-crt|ucrtbase|GetSystemTimePreciseAsFileTime|GetCurrentThreadStackLimits|WaitOnAddress|WakeByAddress|CreateFile2'
assert not re.search(banned, report.split('The Export Tables')[0], re.I)
summary = {'schema': 'yaca-win64-https-candidate-v1', 'target': 'win64-x86_64',
    'curl': '8.21.0', 'mbedtls': '3.6.7', 'downstream_patches': [],
    'image_subsystem': '6.01', 'imports': sorted(imports),
    'sha256': hashlib.sha256((root / 'artifacts/curl.exe').read_bytes()).hexdigest(),
    'runtime_qualified': False}
(root / 'build-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print('win64-https-build=PASS runtime_qualified=false')
PY
