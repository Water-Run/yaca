#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)

if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  export YACA_TEST_MIN_AVAILABLE_MIB=${YACA_TEST_MIN_AVAILABLE_MIB:-4096}
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" bash "$0" "$@"
fi

usage() {
  echo "usage: $0 SOURCE_CACHE OUTPUT" >&2
  exit 64
}

die() {
  echo "win64 HTTPS candidate build: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || usage

SOURCE_CACHE=$(cd "$1" && pwd -P)
OUTPUT_PARENT=$(cd "$(dirname "$2")" && pwd -P)
OUTPUT_ROOT="$OUTPUT_PARENT/$(basename "$2")"

[[ ! -e "$OUTPUT_ROOT" ]] || die "output already exists: $OUTPUT_ROOT"
[[ "$(basename "$OUTPUT_ROOT")" != "." && "$(basename "$OUTPUT_ROOT")" != ".." ]] \
  || die "output basename is unsafe"

for command in awk cp file grep x86_64-w64-mingw32-ar x86_64-w64-mingw32-gcc \
  x86_64-w64-mingw32-objdump x86_64-w64-mingw32-ranlib make sed sha256sum \
  sort strings tar; do
  command -v "$command" >/dev/null 2>&1 \
    || die "required command is missing: $command"
done

[[ "$(uname -s)" == "Linux" ]] || die "this cross-build driver requires Linux"

umask 077
mkdir -p "$OUTPUT_ROOT/logs" "$OUTPUT_ROOT/work" \
  "$OUTPUT_ROOT/prefix/mbedtls/include" "$OUTPUT_ROOT/prefix/mbedtls/lib" \
  "$OUTPUT_ROOT/artifacts"

LOG_ROOT="$OUTPUT_ROOT/logs"
WORK_ROOT="$OUTPUT_ROOT/work"
MBEDTLS_PREFIX="$OUTPUT_ROOT/prefix/mbedtls"
ARTIFACT_ROOT="$OUTPUT_ROOT/artifacts"
CURL_ARCHIVE="$SOURCE_CACHE/curl-8.21.0.tar.xz"
MBEDTLS_ARCHIVE="$SOURCE_CACHE/mbedtls-3.6.7.tar.bz2"

verify_sha256() {
  local path=$1
  local expected=$2
  local actual
  [[ -f "$path" ]] || die "locked input is missing: $path"
  actual=$(sha256sum "$path" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] \
    || die "checksum mismatch for $(basename "$path"): expected=$expected actual=$actual"
}

# win64-x86_64 builds the same locked upstream sources without the win32-xp
# downstream patches: the target floor is Windows 7 SP1, where the upstream
# BCrypt entropy and Vista-era sync primitives are natively available.
verify_sha256 "$CURL_ARCHIVE" \
  aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6
verify_sha256 "$MBEDTLS_ARCHIVE" \
  a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6

tar -xJf "$CURL_ARCHIVE" -C "$WORK_ROOT"
tar -xjf "$MBEDTLS_ARCHIVE" -C "$WORK_ROOT"
CURL_SOURCE="$WORK_ROOT/curl-8.21.0"
MBEDTLS_SOURCE="$WORK_ROOT/mbedtls-3.6.7"

verify_sha256 "$CURL_SOURCE/configure" \
  236bffd8111d66cb9a17a2e64978718a1ee182fce8f25ef8fc99f56393aa3348
verify_sha256 "$CURL_SOURCE/configure.ac" \
  44ab8614c3e824b5bbe0e1d0694211dd8fb9c7ac62c47b3f1e8987dea9ed98a8
verify_sha256 "$CURL_SOURCE/lib/curl_setup.h" \
  8b8233cb31aa58d40965b4d53c428b0e5fc742c041148acbd88bcce5f7ec17cc
verify_sha256 "$CURL_SOURCE/lib/easy_lock.h" \
  1b3abe3b6ff8d78228e6dffbcf954c38fe05283427a8e7bddaaa37d9caa172af
verify_sha256 "$CURL_SOURCE/lib/curl_threads.h" \
  6b23757a99b103e600cd9f8f894dfb2d0cb146f24274f77cad692f7f84a613c0
verify_sha256 "$CURL_SOURCE/lib/curl_threads.c" \
  5233500c2dab55f9a78ca8fab8b134963ff80d8b254f1d3c76bbff2a45927fbc
verify_sha256 "$CURL_SOURCE/lib/rand.c" \
  d13469813cad22319eb68375d464757e01bb162a9775bce29c2407e6da14a661
verify_sha256 "$CURL_SOURCE/lib/curlx/timeval.c" \
  c72e3fa44b771af5f9f5f13343d5a28e9183203e783395d1d76289ac3a51504e
verify_sha256 "$CURL_SOURCE/lib/curlx/fopen.c" \
  ac1ee4422a0e278a41c46173cbd8c0508ec7e382374e968abbf99bf59028116b
verify_sha256 "$CURL_SOURCE/src/tool_getparam.c" \
  b75e73968cf0efe09b1678f35da529196c61558607740390e98f5bc12102b440
verify_sha256 "$CURL_SOURCE/lib/vtls/mbedtls.c" \
  23a7a0ea35e91890c49fac46c8c529393e46f66c26d304356d0e226f5bdf158b
verify_sha256 "$MBEDTLS_SOURCE/library/entropy_poll.c" \
  472e1ba8dfcd751cac88da649987c1422d0e263ffb57ad406bc6652282d48bc4
verify_sha256 "$MBEDTLS_SOURCE/library/platform.c" \
  69f5e0c95478d792ac5654af56817c8272a68c322010e342afacc90e6d57524d
verify_sha256 "$MBEDTLS_SOURCE/include/mbedtls/mbedtls_config.h" \
  004edfaa0f9877a9f3baa7911ab708fd9d7c615f836f6b6674434e337145b7be

require_source_pattern() {
  local path=$1
  local pattern=$2
  local description=$3
  grep -Eq "$pattern" "$path" \
    || die "locked curl config grammar is missing: $description"
}

require_source_pattern "$CURL_SOURCE/src/tool_getparam.c" \
  '\{"http1[.]1",[[:space:]]+ARG_NONE,' "http1.1 standalone option"
require_source_pattern "$CURL_SOURCE/src/tool_getparam.c" \
  '\{"tlsv1[.]2",[[:space:]]+ARG_NONE[|]ARG_TLS,' "tlsv1.2 standalone option"
require_source_pattern "$CURL_SOURCE/src/tool_getparam.c" \
  '\{"proxy-tlsv1",[[:space:]]+ARG_NONE[|]ARG_TLS,' "proxy-tlsv1 standalone option"
for boolean_option in compressed insecure location netrc proxy-insecure retry-all-errors; do
  require_source_pattern "$CURL_SOURCE/src/tool_getparam.c" \
    "\\{\"${boolean_option}\",[[:space:]]+ARG_BOOL" \
    "$boolean_option no-option grammar"
done
grep -Fq 'if(!strncmp(word, "no-", 3))' "$CURL_SOURCE/src/tool_getparam.c" \
  || die "locked curl no-option parser branch is missing"

TLS_PROTOCOLS=$(grep -E '^#define MBEDTLS_SSL_PROTO_TLS' \
  "$MBEDTLS_SOURCE/include/mbedtls/mbedtls_config.h" | awk '{print $2}' | sort)
EXPECTED_TLS_PROTOCOLS=$(printf '%s\n' \
  MBEDTLS_SSL_PROTO_TLS1_2 MBEDTLS_SSL_PROTO_TLS1_3 | sort)
[[ "$TLS_PROTOCOLS" == "$EXPECTED_TLS_PROTOCOLS" ]] \
  || die "Mbed TLS protocol floor is not exactly TLS 1.2 and TLS 1.3"
grep -q 'case CURL_SSLVERSION_TLSv1:' "$CURL_SOURCE/lib/vtls/mbedtls.c" \
  || die "curl Mbed TLS proxy version mapping is missing"
grep -q 'ver_min = MBEDTLS_SSL_VERSION_TLS1_2;' "$CURL_SOURCE/lib/vtls/mbedtls.c" \
  || die "curl Mbed TLS minimum does not map to TLS 1.2"

export SOURCE_DATE_EPOCH=1789344000
export LC_ALL=C
export TZ=UTC

COMMON_DEFINES="-DWINVER=0x0601 -D_WIN32_WINNT=0x0601"
COMMON_CFLAGS="-Os -ffunction-sections -fdata-sections"
COMMON_LDFLAGS="-static -Wl,--gc-sections -Wl,--build-id=none \
-Wl,--major-subsystem-version,6,--minor-subsystem-version,1"

if ! make -C "$MBEDTLS_SOURCE" -j1 lib \
  CC=x86_64-w64-mingw32-gcc AR=x86_64-w64-mingw32-ar ARFLAGS=rcD \
  CFLAGS="-std=c99 $COMMON_CFLAGS $COMMON_DEFINES" \
  >"$LOG_ROOT/mbedtls-build.log" 2>&1; then
  tail -80 "$LOG_ROOT/mbedtls-build.log" >&2
  die "Mbed TLS build failed"
fi
cp -a "$MBEDTLS_SOURCE/include/mbedtls" "$MBEDTLS_PREFIX/include/"
cp -a "$MBEDTLS_SOURCE/include/psa" "$MBEDTLS_PREFIX/include/"
cp "$MBEDTLS_SOURCE/library/libmbedcrypto.a" \
  "$MBEDTLS_SOURCE/library/libmbedx509.a" \
  "$MBEDTLS_SOURCE/library/libmbedtls.a" "$MBEDTLS_PREFIX/lib/"

if ! (
  cd "$CURL_SOURCE"
  # Upstream's mbedtls probe does not add -lbcrypt for Windows targets, so
  # the unpatched 64-bit entropy source fails to link during detection.
  env CC=x86_64-w64-mingw32-gcc AR=x86_64-w64-mingw32-ar \
    RANLIB=x86_64-w64-mingw32-ranlib \
    CFLAGS="$COMMON_CFLAGS" \
    CPPFLAGS="$COMMON_DEFINES -I$MBEDTLS_PREFIX/include" \
    LDFLAGS="-L$MBEDTLS_PREFIX/lib $COMMON_LDFLAGS" PKG_CONFIG=false \
    LIBS="-lbcrypt" \
    ./configure \
      --host=x86_64-w64-mingw32 --disable-shared --enable-static \
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
      --disable-threaded-resolver --disable-ipv6 --disable-sspi \
      --disable-negotiate-auth --disable-kerberos-auth \
      --without-zlib --without-brotli --without-zstd --without-libpsl \
      --without-libidn2 --without-nghttp2 --without-ngtcp2 \
      --without-nghttp3 --without-libssh2 --without-libgsasl \
      --without-gssapi --without-ca-bundle --without-ca-path \
      --without-ca-fallback --without-ca-embed --without-openssl \
      --without-gnutls --without-wolfssl --without-rustls \
      --without-schannel --without-amissl --with-mbedtls="$MBEDTLS_PREFIX"
  make -j1
) >"$LOG_ROOT/curl-build.log" 2>&1; then
  tail -120 "$LOG_ROOT/curl-build.log" >&2
  die "curl build failed"
fi

cp "$CURL_SOURCE/src/curl.exe" "$ARTIFACT_ROOT/curl.exe"
file "$ARTIFACT_ROOT/curl.exe" >"$OUTPUT_ROOT/curl-file.txt"
x86_64-w64-mingw32-objdump -p "$ARTIFACT_ROOT/curl.exe" \
  >"$OUTPUT_ROOT/curl-objdump.txt"
sha256sum "$ARTIFACT_ROOT/curl.exe" >"$OUTPUT_ROOT/artifact-sha256.txt"
strings "$ARTIFACT_ROOT/curl.exe" >"$OUTPUT_ROOT/curl-strings.txt"

grep -Eq 'PE32\+ executable.*console.*x86-64' "$OUTPUT_ROOT/curl-file.txt" \
  || die "curl is not a PE32+ x86-64 console image"
grep -Eq '^MajorSubsystemVersion[[:space:]]+6$' "$OUTPUT_ROOT/curl-objdump.txt" \
  || die "PE major subsystem version is not 6"
grep -Eq '^MinorSubsystemVersion[[:space:]]+1$' "$OUTPUT_ROOT/curl-objdump.txt" \
  || die "PE minor subsystem version is not 1"

# The Windows 7 SP1 floor makes the 64-bit msvcrt.dll's own secure-CRT
# surface (wcstombs_s and friends) a bundled import, so only genuinely
# unbundled CRT linkage is rejected here; the DLL closure check above
# remains the hard dependency guarantee.
BANNED_IMPORTS='api-ms-win-crt|ucrtbase'
if grep -Ei "$BANNED_IMPORTS" "$OUTPUT_ROOT/curl-objdump.txt"; then
  die "curl imports an unbundled CRT symbol"
fi

for required_import in getaddrinfo BCryptGenRandom; do
  grep -q "$required_import" "$OUTPUT_ROOT/curl-objdump.txt" \
    || die "required win64 import is missing: $required_import"
done

DLLS=$(sed -n 's/^[[:space:]]*DLL Name: //p' "$OUTPUT_ROOT/curl-objdump.txt" | sort -u)
for dll in $DLLS; do
  case "$dll" in
    ADVAPI32.dll|KERNEL32.dll|WS2_32.dll|bcrypt.dll|msvcrt.dll) ;;
    *) die "unexpected runtime DLL closure member: $dll" ;;
  esac
done

grep -q '^libcurl/8\.21\.0$' "$OUTPUT_ROOT/curl-strings.txt" \
  || die "curl version marker is missing"
grep -q '^TLSv1\.2 or greater$' "$OUTPUT_ROOT/curl-strings.txt" \
  || die "TLS 1.2 carrier support marker is missing"

{
  echo "schema=yaca-win64-https-candidate-v1"
  echo "status=PASS"
  echo "target=win64-x86_64"
  echo "minimum-image-subsystem=Windows-6.1"
  echo "evidence=cross-build-and-static-import-audit"
  echo "curl=8.21.0"
  echo "curl_downstream_patches=none"
  echo "mbedtls=3.6.7"
  echo "mbedtls_downstream_patches=none"
  echo "protocols=http,https"
  echo "curl_config_grammar=standalone-no-option"
  echo "minimum_tls=TLSv1.2-or-newer"
  echo "proxy_tls_floor=TLSv1.2-or-newer-via-mbedtls"
  echo "resolver=blocking"
  echo "ipv6=false"
  echo "entropy=BCryptGenRandom"
  echo "runtime_qualified=false"
  echo "real_windows7_https_proof=pending"
  echo "release_authorized=false"
} >"$OUTPUT_ROOT/build-summary.txt"

cat "$OUTPUT_ROOT/build-summary.txt"
