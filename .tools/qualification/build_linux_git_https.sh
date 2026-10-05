#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-10-05
# File: build_linux_git_https.sh
# Description: Builds relocatable Git 2.55.0 with static HTTP/TLS dependencies on the CentOS 7 baseline.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
YACA_TEST_MIN_AVAILABLE_MIB=${YACA_TEST_MIN_AVAILABLE_MIB:-5120}
[[ "$YACA_TEST_MIN_AVAILABLE_MIB" =~ ^[1-9][0-9]{0,6}$ \
  && "$YACA_TEST_MIN_AVAILABLE_MIB" -le 1048576 ]] || exit 75
(( YACA_TEST_MIN_AVAILABLE_MIB >= 5120 )) || YACA_TEST_MIN_AVAILABLE_MIB=5120
export YACA_TEST_MIN_AVAILABLE_MIB
if [[ ${YACA_LINUX_GIT_BUILD_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" \
    env YACA_LINUX_GIT_BUILD_GUARD_HELD=1 bash "$0" "$@"
fi

# Stop the Git build before a failed input or incompatible host can be published.
#@param ... string Diagnostic words joined by the shell argument separator.
#@return void Does not return; exits with status one.
#@effect Writes the diagnostic to stderr and terminates the build process.
die() {
  echo "linux Git HTTPS: $*" >&2
  exit 1
}

# Verify one source archive against its frozen SHA-256 before extracting it.
#@param 1 string Existing archive path.
#@param 2 string Expected lowercase SHA-256.
#@return void No value; a missing or changed archive terminates through die.
#@effect Reads the source archive and prints no source contents.
verify_source() {
  [[ -f "$1" ]] || die "source is missing: $1"
  [[ $(sha256sum "$1" | awk '{print $1}') == "$2" ]] \
    || die "source SHA-256 differs: $1"
}

# Reject ELF imports requiring a glibc symbol version above the CentOS 7 baseline.
#@param 1 string Existing ELF executable path.
#@param 2 string New diagnostic output path within this build's log directory.
#@return void No value; newer symbol requirements terminate through die.
#@effect Reads ELF version metadata and writes the complete readelf record.
verify_abi() {
  readelf --version-info "$1" > "$2"
  awk '
    /Name: GLIBC_[0-9.]+/ {
      for (column = 1; column <= NF; column++) {
        if ($column ~ /^GLIBC_[0-9.]+$/) {
          value = $column
          sub(/^GLIBC_/, "", value)
          split(value, parts, ".")
          if (parts[1] > 2 || (parts[1] == 2 && parts[2] > 17) ||
              (parts[1] == 2 && parts[2] == 17 && parts[3] > 0)) exit 1
        }
      }
    }
  ' "$2" || die "glibc 2.17 baseline exceeded: $1"
}

[[ $# == 7 ]] || die "usage: $0 FULL_SOURCES CURL_BUILD MBEDTLS_PREFIX COMPILER_PREFIX ZLIB_BUILD PERL_PREFIX NEW_OUTPUT"
SOURCES=$(cd "$1" && pwd -P)
CURL_BUILD=$(cd "$2" && pwd -P)
MBEDTLS_PREFIX=$(cd "$3" && pwd -P)
COMPILER_PREFIX=$(cd "$4" && pwd -P)
ZLIB_BUILD=$(cd "$5" && pwd -P)
PERL_PREFIX=$(cd "$6" && pwd -P)
OUTPUT_PARENT=$(cd "$(dirname "$7")" && pwd -P)
OUTPUT_ROOT="$OUTPUT_PARENT/$(basename "$7")"
[[ ! -e "$OUTPUT_ROOT" ]] || die "output already exists"
[[ -f /etc/centos-release ]] || die "CentOS 7 build host is required"
[[ $(getconf GNU_LIBC_VERSION) == 'glibc 2.17' ]] || die "glibc 2.17 build host is required"
grep -Eq '^CentOS Linux release 7\.' /etc/centos-release || die "CentOS 7 build host is required"
for command in awk cp find getconf grep ln mkdir perl readelf sha256sum sort tar; do
  command -v "$command" >/dev/null || die "required build command is missing: $command"
done
CC="$COMPILER_PREFIX/bin/gcc"
MAKE="$COMPILER_PREFIX/bin/make"
[[ -x "$CC" && -x "$MAKE" ]] || die "portable compiler and Make are required"
[[ $("$CC" -dumpfullversion) == 13.5.0 ]] || die "GCC 13.5.0 is required"
[[ -x "$PERL_PREFIX/bin/perl" && -f "$PERL_PREFIX/COPYING.Perl" \
  && -f "$PERL_PREFIX/ARTISTIC.Perl" ]] || die "relocatable Perl runtime and licenses are required"
[[ $("$PERL_PREFIX/bin/perl" -e 'print $^V') == v5.42.3 ]] || die "Perl 5.42.3 is required"
verify_source "$SOURCES/git-2.55.0.tar.xz" \
  457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357
verify_source "$SOURCES/gcc-13.5.0.tar.xz" \
  ec3df0015ed01411f91f9a9cd5b4da3070eb1222b02fadf4133c30c090399855
for library in "$CURL_BUILD/lib/.libs/libcurl.a" "$ZLIB_BUILD/libz.a" \
  "$MBEDTLS_PREFIX/../expat/lib/libexpat.a" \
  "$MBEDTLS_PREFIX/lib/libmbedtls.a" "$MBEDTLS_PREFIX/lib/libmbedx509.a" \
  "$MBEDTLS_PREFIX/lib/libmbedcrypto.a"; do
  [[ -f "$library" ]] || die "static dependency is missing: $library"
done
grep -Eq '#define LIBCURL_VERSION "8\.21\.0"' "$CURL_BUILD/include/curl/curlver.h" \
  || die "libcurl headers are not version 8.21.0"

umask 077
mkdir -p "$OUTPUT_ROOT/work" "$OUTPUT_ROOT/logs" "$OUTPUT_ROOT/dependencies/include" \
  "$OUTPUT_ROOT/dependencies/lib" "$OUTPUT_ROOT/stage"
WORK_ROOT="$OUTPUT_ROOT/work"
LOG_ROOT="$OUTPUT_ROOT/logs"
DEPENDENCIES="$OUTPUT_ROOT/dependencies"
cp -R "$CURL_BUILD/include/curl" "$DEPENDENCIES/include/curl"
cp "$CURL_BUILD/lib/.libs/libcurl.a" "$DEPENDENCIES/lib/libcurl.a"
cp "$MBEDTLS_PREFIX/lib/"libmbed*.a "$DEPENDENCIES/lib/"
cp "$MBEDTLS_PREFIX/../expat/lib/libexpat.a" "$DEPENDENCIES/lib/libexpat.a"
cp "$MBEDTLS_PREFIX/../expat/include/"expat*.h "$DEPENDENCIES/include/"
cp "$ZLIB_BUILD/libz.a" "$DEPENDENCIES/lib/libz.a"
tar -C "$WORK_ROOT" -xJf "$SOURCES/git-2.55.0.tar.xz"
tar -xJOf "$SOURCES/gcc-13.5.0.tar.xz" gcc-13.5.0/zlib/zlib.h > "$DEPENDENCIES/include/zlib.h"
tar -xJOf "$SOURCES/gcc-13.5.0.tar.xz" gcc-13.5.0/zlib/zconf.h > "$DEPENDENCIES/include/zconf.h"
GIT_SOURCE="$WORK_ROOT/git-2.55.0"
export PATH="$PERL_PREFIX/bin:$COMPILER_PREFIX/bin:$PATH" LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1791158400
export MAKEFLAGS=-j1 MFLAGS=-j1

# Keep HTTP(S), file/SSH, Perl helpers and SHA-1 collision detection. The
# command-line toolbox excludes Tcl GUI and the optional Python p4 command,
# matching the existing CLI edition. /dev/urandom also works on kernel 3.10;
# newer getrandom declarations are not available in CentOS 7 headers.
BUILD_OPTIONS=(
  -C "$GIT_SOURCE" -j1 CC="$CC" prefix=/yaca/tools/git
  RUNTIME_PREFIX=YesPlease CSPRNG_METHOD=none NO_RUST=YesPlease
  'PERL_PATH=/usr/bin/env perl'
  NO_GETTEXT=YesPlease NO_TCLTK=YesPlease NO_PYTHON=YesPlease
  NO_OPENSSL=YesPlease NO_CURL= CURLDIR="$DEPENDENCIES" ZLIB_PATH="$DEPENDENCIES" EXPATDIR="$DEPENDENCIES"
  CURL_LDFLAGS="$DEPENDENCIES/lib/libcurl.a $DEPENDENCIES/lib/libmbedtls.a $DEPENDENCIES/lib/libmbedx509.a $DEPENDENCIES/lib/libmbedcrypto.a -lpthread -lm"
  CC_LD_DYNPATH= CFLAGS="-O2 -ffunction-sections -fdata-sections" LDFLAGS="-static-libgcc -Wl,--gc-sections"
)
if ! "$MAKE" "${BUILD_OPTIONS[@]}" all > "$LOG_ROOT/build.log" 2>&1; then
  tail -90 "$LOG_ROOT/build.log" >&2
  die "Git build failed"
fi
if ! "$MAKE" "${BUILD_OPTIONS[@]}" DESTDIR="$OUTPUT_ROOT/stage" install \
    > "$LOG_ROOT/install.log" 2>&1; then
  tail -90 "$LOG_ROOT/install.log" >&2
  die "Git install failed"
fi
mv "$OUTPUT_ROOT/stage/yaca/tools/git" "$OUTPUT_ROOT/git"
cp -a "$PERL_PREFIX/." "$OUTPUT_ROOT/git/"
# Git puts its helper directory in PATH before launching ancillary commands.
# The dispatcher reaches the real Perl binary at its bin/ path so the runtime's
# relocatable @INC calculation uses the same layout as its Configure prefix.
cat > "$OUTPUT_ROOT/git/libexec/git-core/perl" <<'SH'
#!/bin/sh
# Author: WaterRun
# Date: 2026-10-05
# File: perl
# Description: Dispatch Git helpers to their adjacent relocatable Perl runtime.
YACA_GIT_HELPER_DIR=$(CDPATH= cd -- "${0%/*}" && pwd -P) || exit 1
exec "$YACA_GIT_HELPER_DIR/../../bin/perl" "$@"
SH
chmod 755 "$OUTPUT_ROOT/git/libexec/git-core/perl"
cp "$GIT_SOURCE/COPYING" "$OUTPUT_ROOT/git/COPYING"
for name in git-remote-http git-remote-https; do
  [[ -x "$OUTPUT_ROOT/git/libexec/git-core/$name" ]] || die "HTTP(S) helper is missing: $name"
done
"$OUTPUT_ROOT/git/bin/git" --version > "$LOG_ROOT/version.txt"
grep -Fxq 'git version 2.55.0' "$LOG_ROOT/version.txt" || die "Git version differs"
verify_abi "$OUTPUT_ROOT/git/bin/git" "$LOG_ROOT/git-symbols.txt"
verify_abi "$OUTPUT_ROOT/git/libexec/git-core/git-remote-http" "$LOG_ROOT/http-symbols.txt"
readelf -d "$OUTPUT_ROOT/git/libexec/git-core/git-remote-http" > "$LOG_ROOT/http-dependencies.txt"
if grep -Eq '\((RPATH|RUNPATH)\)' "$LOG_ROOT/http-dependencies.txt"; then
  die "HTTP(S) helper retained a build-directory search path"
fi
if grep -Eq 'Shared library:.*(libcurl|libmbed|libssl|libcrypto|libz\.so|libexpat)' "$LOG_ROOT/http-dependencies.txt"; then
  die "HTTP(S) helper leaked a non-system dynamic dependency"
fi
{
  echo schema=yaca-linux-git-https-build-v1
  echo status=PASS
  echo target=linux-x86_64
  echo git=2.55.0
  echo curl=8.21.0
  echo tls=mbedtls-3.6.7
  echo compiler=GCC-13.5.0
  echo perl=5.42.3-relocatable-static-libperl
  echo libc=glibc-2.17
  echo build_jobs=1
  echo random_source=/dev/urandom
  echo release_authorized=false
  echo target_qualification_complete=false
  sha256sum "$OUTPUT_ROOT/git/bin/git" "$OUTPUT_ROOT/git/libexec/git-core/git-remote-http" \
    "$DEPENDENCIES/lib/"*.a
} > "$OUTPUT_ROOT/build-summary.txt"
echo "linux-git-https-build=PASS qualification=pending"
