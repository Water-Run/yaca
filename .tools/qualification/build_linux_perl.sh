#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-10-05
# File: build_linux_perl.sh
# Description: Builds the relocatable Perl runtime used by Linux Git helpers on the glibc 2.17 baseline.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
export YACA_TEST_MIN_AVAILABLE_MIB=5120
if [[ ${YACA_LINUX_PERL_BUILD_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" \
    env YACA_LINUX_PERL_BUILD_GUARD_HELD=1 bash "$0" "$@"
fi

# Stop the build before accepting missing inputs, failed tests or incompatible runtime libraries.
#@param ... string Diagnostic words joined with the shell argument separator.
#@return void No normal return; exits the build with status one.
#@effect Writes a diagnostic to stderr and terminates this build.
die() {
  echo "linux Perl: $*" >&2
  exit 1
}

# Reject one Perl executable or extension with newer glibc imports or fixed runtime search paths.
#@param 1 string Existing ELF artifact within the new runtime tree.
#@return void No result; incompatible artifacts terminate through die.
#@effect Reads ELF dynamic and version metadata without executing the artifact.
verify_elf() {
  local artifact=$1
  readelf -d "$artifact" | grep -Eq '\((RPATH|RUNPATH)\)' \
    && die "runtime search path is not relocatable: $artifact"
  readelf --version-info "$artifact" | awk '
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
  ' || die "glibc 2.17 baseline exceeded: $artifact"
}

[[ $# == 3 ]] || die "usage: $0 SOURCE_CACHE COMPILER_PREFIX NEW_OUTPUT"
SOURCES=$(cd "$1" && pwd -P)
COMPILER=$(cd "$2" && pwd -P)
OUTPUT_PARENT=$(cd "$(dirname "$3")" && pwd -P)
OUTPUT_ROOT="$OUTPUT_PARENT/$(basename "$3")"
[[ ! -e "$OUTPUT_ROOT" ]] || die "output already exists"
[[ -f /etc/centos-release && $(getconf GNU_LIBC_VERSION) == 'glibc 2.17' ]] \
  || die "CentOS 7 build host is required"
export PATH="$COMPILER/bin:$PATH" LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1791158400
for command in awk cp find getconf grep make mkdir readelf sha256sum sort tar; do
  command -v "$command" >/dev/null || die "required command is missing: $command"
done
[[ $(gcc -dumpfullversion) == 13.5.0 ]] || die "GCC 13.5.0 is required"
ARCHIVE="$SOURCES/perl-5.42.3.tar.xz"
[[ -f "$ARCHIVE" && $(sha256sum "$ARCHIVE" | awk '{print $1}') \
  == c9387e1473a1866935cb047ece7c2e0a80767a3acdecb79d4a375f8a95970ddc ]] \
  || die "Perl source does not match the upstream SHA-256"
CRYPT_ARCHIVE="$SOURCES/libxcrypt-4.4.38.tar.xz"
[[ -f "$CRYPT_ARCHIVE" && $(sha256sum "$CRYPT_ARCHIVE" | awk '{print $1}') \
  == 80304b9c306ea799327f01d9a7549bdb28317789182631f1b54f4511b4206dd6 ]] \
  || die "libxcrypt source does not match its SHA-256"
umask 077
mkdir -p "$OUTPUT_ROOT/work" "$OUTPUT_ROOT/logs" "$OUTPUT_ROOT/stage"
tar -C "$OUTPUT_ROOT/work" -xJf "$CRYPT_ARCHIVE"
CRYPT_PREFIX="$OUTPUT_ROOT/prefix/libxcrypt"
(
  cd "$OUTPUT_ROOT/work/libxcrypt-4.4.38"
  CC="$COMPILER/bin/gcc" ./configure --prefix="$CRYPT_PREFIX" --disable-shared --enable-static \
    --disable-werror > "$OUTPUT_ROOT/logs/crypt-configure.log" 2>&1 || exit 1
  make -j1 > "$OUTPUT_ROOT/logs/crypt-build.log" 2>&1 || exit 1
  make -j1 check > "$OUTPUT_ROOT/logs/crypt-test.log" 2>&1 || exit 1
  make -j1 install > "$OUTPUT_ROOT/logs/crypt-install.log" 2>&1 || exit 1
) || die "static libxcrypt configure, build, test or install failed"
tar -C "$OUTPUT_ROOT/work" -xJf "$ARCHIVE"
SOURCE="$OUTPUT_ROOT/work/perl-5.42.3"
(
  cd "$SOURCE"
  sh Configure -des -Dprefix=/yaca/tools/git -Duserelocatableinc -Uuseshrplib \
    -Dcc="env -u LD_RUN_PATH $COMPILER/bin/gcc" \
    -Dld="env -u LD_RUN_PATH $COMPILER/bin/gcc" -Dldflags="-static-libgcc -L$CRYPT_PREFIX/lib" \
    -Dccflags="-I$CRYPT_PREFIX/include" \
    -Dlibs="-lcrypt -lpthread -ldl -lm -lutil -lc" \
    -Dman1dir=none -Dman3dir=none -Ui_db -Ui_gdbm -Ui_ndbm \
    > "$OUTPUT_ROOT/logs/configure.log" 2>&1 || exit 1
  make -j1 LD_RUN_PATH= > "$OUTPUT_ROOT/logs/build.log" 2>&1 || exit 1
  make -j1 LD_RUN_PATH= test TEST_JOBS=1 > "$OUTPUT_ROOT/logs/test.log" 2>&1 || exit 1
  make -j1 LD_RUN_PATH= install DESTDIR="$OUTPUT_ROOT/stage" \
    > "$OUTPUT_ROOT/logs/install.log" 2>&1 || exit 1
) || die "Perl configure, build, test or install failed; inspect the saved logs"
mv "$OUTPUT_ROOT/stage/yaca/tools/git" "$OUTPUT_ROOT/perl"
cp "$SOURCE/Copying" "$OUTPUT_ROOT/perl/COPYING.Perl"
cp "$SOURCE/Artistic" "$OUTPUT_ROOT/perl/ARTISTIC.Perl"
cp "$OUTPUT_ROOT/work/libxcrypt-4.4.38/COPYING.LIB" "$OUTPUT_ROOT/perl/COPYING.libxcrypt"
cp "$OUTPUT_ROOT/work/libxcrypt-4.4.38/LICENSING" "$OUTPUT_ROOT/perl/LICENSING.libxcrypt"
verify_elf "$OUTPUT_ROOT/perl/bin/perl"
while IFS= read -r extension; do
  verify_elf "$extension"
done < <(find "$OUTPUT_ROOT/perl" -type f -name '*.so' | sort)
"$OUTPUT_ROOT/perl/bin/perl" -MConfig -MFile::Spec -MPOSIX -MNet::SMTP -e \
  'die "version" unless $^V eq v5.42.3; die "relocation" unless $Config{userelocatableinc} eq "define"; print "perl-runtime=PASS\n"' \
  > "$OUTPUT_ROOT/logs/runtime.log"
{
  echo schema=yaca-linux-perl-build-v1
  echo status=PASS
  echo version=5.42.3
  echo target=linux-x86_64
  echo libc=glibc-2.17
  echo build_jobs=1
  echo prefix=/yaca/tools/git
  echo relocation=userelocatableinc
  echo shared_libperl=false
  echo crypt=libxcrypt-4.4.38-static
  sha256sum "$ARCHIVE" "$CRYPT_ARCHIVE" "$OUTPUT_ROOT/perl/bin/perl"
} > "$OUTPUT_ROOT/build-summary.txt"
echo 'linux-perl-build=PASS qualification=pending'
